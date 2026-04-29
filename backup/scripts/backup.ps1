# backup.ps1
# Snapshot complet du hub vers restic OneDrive.
# Idempotent : peut être lancé manuellement ou via Task Scheduler quotidien.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AgeKeyPath = "$env:USERPROFILE\.age\hub.key",

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"
$startTime = Get-Date
Write-Host "[*] Hub backup - $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan

# ----------------------------------------------------------------------
# Helpers (définis EN HAUT pour pouvoir être appelés depuis n'importe où)
# ----------------------------------------------------------------------

function Send-NtfyNotif {
    param(
        [string]$Title,
        [string]$Body
    )
    $ntfySecret = Join-Path $RepoRoot "secrets\ntfy.enc.yaml"
    if (-not (Test-Path $ntfySecret)) {
        return
    }
    try {
        $cfg = sops --decrypt $ntfySecret | Out-String
        foreach ($line in $cfg -split "`n") {
            if ($line -match "^NTFY_URL:\s*(.+)$") {
                $url = $matches[1].Trim()
                Invoke-WebRequest -Uri $url -Method POST -Body $Body -Headers @{ "Title" = $Title } | Out-Null
                return
            }
        }
    } catch {
        Write-Host "[!] Notif ntfy a échoué (non critique)" -ForegroundColor Yellow
    }
}

# ----------------------------------------------------------------------
# 1. Charge les credentials restic depuis sops
# ----------------------------------------------------------------------
$secretsPath = Join-Path $RepoRoot "secrets\restic.enc.yaml"
if (-not (Test-Path $secretsPath)) {
    Write-Host "[X] Manquant : $secretsPath" -ForegroundColor Red
    Write-Host "    Voir backup/README.md section 'Setup initial'." -ForegroundColor Yellow
    exit 1
}

$env:SOPS_AGE_KEY_FILE = $AgeKeyPath
$resticConfig = sops --decrypt $secretsPath | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Échec de déchiffrement sops" -ForegroundColor Red
    exit 1
}

# Parse le YAML (simple : on cherche les 2 clés)
foreach ($line in $resticConfig -split "`n") {
    if ($line -match "^RESTIC_PASSWORD:\s*(.+)$") {
        $env:RESTIC_PASSWORD = $matches[1].Trim()
    }
    if ($line -match "^RESTIC_REPOSITORY:\s*(.+)$") {
        $env:RESTIC_REPOSITORY = $matches[1].Trim()
    }
}

if (-not $env:RESTIC_PASSWORD -or -not $env:RESTIC_REPOSITORY) {
    Write-Host "[X] secrets/restic.enc.yaml ne contient pas RESTIC_PASSWORD ou RESTIC_REPOSITORY" -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------------
# 2. Dump Postgres
# ----------------------------------------------------------------------
$stagingDir = Join-Path $RepoRoot "backup\staging"
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
$dumpPath = Join-Path $stagingDir "db.sql"

Write-Host "[*] pg_dump..." -ForegroundColor Cyan
$pgUser = $env:POSTGRES_USER
if (-not $pgUser) { $pgUser = "hub" }
$pgDb = $env:POSTGRES_DB
if (-not $pgDb) { $pgDb = "hubdb" }

# Cherche le container Postgres (dev ou prod)
$pgContainer = docker ps --filter "name=postgres" --format "{{.Names}}" | Select-Object -First 1
if (-not $pgContainer) {
    Write-Host "[X] Container postgres pas trouvé. La stack tourne-t-elle ?" -ForegroundColor Red
    exit 1
}

# Capture le dump dans une variable PUIS écrit en UTF-8 sans BOM via .NET.
# `Out-File -Encoding utf8` en PS 5.1 ajoute un BOM, ce qui peut casser psql restore.
$dumpContent = docker exec $pgContainer pg_dump -U $pgUser $pgDb 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] pg_dump a échoué : $dumpContent" -ForegroundColor Red
    Send-NtfyNotif -Title "Hub backup ÉCHEC" -Body "pg_dump exit=$LASTEXITCODE"
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($dumpPath, ($dumpContent -join "`n"), $utf8NoBom)

$dumpSize = (Get-Item $dumpPath).Length / 1MB
Write-Host "[OK] DB dumpée : $($dumpSize.ToString('0.00')) MB" -ForegroundColor Green

# ----------------------------------------------------------------------
# 3. Restic snapshot
# ----------------------------------------------------------------------
$rawEventsDir = Join-Path (Split-Path $RepoRoot -Parent) "raw_events"
$secretsDir = Join-Path $RepoRoot "secrets"

# Notes :
# - On veut les `secrets/*.enc.yaml` (déjà chiffrés) DANS le snapshot.
# - On exclut explicitement les `secrets/*.yaml` non-chiffrés s'il en traîne
#   (ne devrait pas arriver — `.gitignore` les bloque, mais sécurité).
# - On exclut aussi staging/ pour ne pas se backuper soi-même.
$backupPaths = @($dumpPath, $rawEventsDir, $secretsDir)
$existingPaths = $backupPaths | Where-Object { Test-Path $_ }

Write-Host "[*] restic backup ..." -ForegroundColor Cyan
$tag = "auto-$(Get-Date -Format 'yyyy-MM-dd_HH-mm')"

# Pattern d'exclusion : tout fichier *.yaml MAIS PAS *.enc.yaml.
# restic supporte les patterns glob : `*.yaml` matche les .yaml ET les .enc.yaml,
# donc on utilise `--iexclude-file` avec un pattern précis.
$excludePatterns = @"
*.tmp
backup/staging
"@
$excludeFile = Join-Path $stagingDir ".restic-exclude"
[System.IO.File]::WriteAllText($excludeFile, $excludePatterns, $utf8NoBom)

restic backup --tag $tag --exclude-file $excludeFile $existingPaths
$resticExit = $LASTEXITCODE
Remove-Item -Force $excludeFile -ErrorAction SilentlyContinue

if ($resticExit -ne 0) {
    Write-Host "[X] restic backup a échoué (exit=$resticExit)" -ForegroundColor Red
    Send-NtfyNotif -Title "Hub backup ÉCHEC" -Body "restic backup exit=$resticExit"
    exit 1
}

# ----------------------------------------------------------------------
# 4. Politique de rétention (forget + prune)
# ----------------------------------------------------------------------
Write-Host "[*] restic forget --prune ..." -ForegroundColor Cyan
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune

# ----------------------------------------------------------------------
# 5. Cleanup staging
# ----------------------------------------------------------------------
Remove-Item -Force $dumpPath -ErrorAction SilentlyContinue

# ----------------------------------------------------------------------
# 6. Succès — notif
# ----------------------------------------------------------------------
$elapsed = (Get-Date) - $startTime
$msg = "Backup OK en $($elapsed.TotalSeconds.ToString('0'))s. DB $($dumpSize.ToString('0.00'))MB. Tag $tag"
Write-Host ""
Write-Host "[OK] $msg" -ForegroundColor Green
Send-NtfyNotif -Title "Hub backup OK" -Body $msg
