# backup-hub.ps1
# Backup chiffré du hub vers Drive via restic.
#
# Sauvegarde:
#   - Postgres dump (toutes les data: transactions, locations, oauth tokens)
#   - raw_events/ (event sourcing, immutable - cf. ADR-0002)
#   - inbox/ (CSV/PDF en attente d'ingest)
#   - hub-deploy/.env (config + secrets)
#
# Restic chiffre tout avec un password (différent du master Marc).
# Le repo restic est sur Drive : G:\...\Hub perso\backups-restic\
#
# Usage:
#   .\scripts\backup-hub.ps1            # backup interactif (demande password)
#   .\scripts\backup-hub.ps1 -Init      # init du repo restic une fois
#   $env:RESTIC_PASSWORD="..."; .\scripts\backup-hub.ps1 -Quiet  # automation cron

param(
    [switch]$Init,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

# ── Config ───────────────────────────────────────────────────────────────────

$root = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso"
$resticRepo = "$root\backups-restic"
$envFile = "$root\hub-deploy\.env"
$rawEventsDir = "$root\raw_events"
$inboxDir = "$root\inbox"

# ── Find restic ──────────────────────────────────────────────────────────────

$restic = Get-Command restic -ErrorAction SilentlyContinue
if (-not $restic) {
    # Try winget locations
    $candidates = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter "restic.exe" -Recurse -ErrorAction SilentlyContinue
    if ($candidates) { $restic = $candidates[0].FullName } else { $restic = $null }
} else {
    $restic = $restic.Source
}

if (-not $restic) {
    Write-Host "[X] restic n'est pas installe. Installation:" -ForegroundColor Red
    Write-Host "    winget install restic.restic" -ForegroundColor Yellow
    exit 1
}

# ── Get password ─────────────────────────────────────────────────────────────

$pwd = $env:RESTIC_PASSWORD
if (-not $pwd) {
    if ($Quiet) {
        Write-Host "[X] RESTIC_PASSWORD env var requise en mode -Quiet" -ForegroundColor Red
        exit 1
    }
    $sec = Read-Host "Password restic (different du master Marc)" -AsSecureString
    $pwd = [System.Net.NetworkCredential]::new("", $sec).Password
}
$env:RESTIC_PASSWORD = $pwd
$env:RESTIC_REPOSITORY = $resticRepo

# ── Init mode ────────────────────────────────────────────────────────────────

if ($Init) {
    if (Test-Path $resticRepo) {
        Write-Host "[!] Repo restic existe deja: $resticRepo" -ForegroundColor Yellow
        Write-Host "    Pour reset: rm -r '$resticRepo' (PERTE des backups existants)" -ForegroundColor DarkGray
        exit 0
    }
    Write-Host "[*] Init du repo restic dans $resticRepo..." -ForegroundColor Cyan
    & $restic init
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Repo initialise. Tu peux maintenant backuper:" -ForegroundColor Green
        Write-Host "    .\scripts\backup-hub.ps1" -ForegroundColor White
    }
    exit $LASTEXITCODE
}

# ── Sanity check repo exists ─────────────────────────────────────────────────

if (-not (Test-Path $resticRepo)) {
    Write-Host "[X] Repo restic absent. Lance d'abord:" -ForegroundColor Red
    Write-Host "    .\scripts\backup-hub.ps1 -Init" -ForegroundColor Yellow
    exit 1
}

# ── Postgres dump (si Docker tourne) ─────────────────────────────────────────

$tempDumpDir = "$env:TEMP\hub-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path $tempDumpDir | Out-Null

$dockerExists = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerExists) {
    $pgRunning = docker ps --filter "name=hub-dev-postgres" --format "{{.Names}}" 2>$null
    if ($pgRunning) {
        if (-not $Quiet) { Write-Host "[*] Postgres dump..." -ForegroundColor Cyan }
        $envContent = Get-Content $envFile -ErrorAction SilentlyContinue
        $pgUser = ($envContent | Select-String "POSTGRES_USER=").Line -replace ".*=", ""
        $pgDb = ($envContent | Select-String "POSTGRES_DB=").Line -replace ".*=", ""
        $dumpPath = "$tempDumpDir\postgres-dump.sql"
        & docker exec hub-dev-postgres-1 pg_dump -U $pgUser -d $pgDb 2>&1 > $dumpPath
        if (Test-Path $dumpPath) {
            $size = (Get-Item $dumpPath).Length
            if (-not $Quiet) { Write-Host "  [OK] Dump $([math]::Round($size/1KB)) KB" -ForegroundColor Green }
        }
    } else {
        if (-not $Quiet) { Write-Host "[!] Postgres pas en cours - skip dump" -ForegroundColor Yellow }
    }
}

# ── Restic backup ────────────────────────────────────────────────────────────

if (-not $Quiet) { Write-Host "[*] Restic backup en cours..." -ForegroundColor Cyan }

$backupPaths = @()
if (Test-Path $envFile) { $backupPaths += $envFile }
if (Test-Path $rawEventsDir) { $backupPaths += $rawEventsDir }
if (Test-Path $inboxDir) { $backupPaths += $inboxDir }
if ((Get-ChildItem $tempDumpDir -ErrorAction SilentlyContinue).Count -gt 0) { $backupPaths += $tempDumpDir }

if ($backupPaths.Count -eq 0) {
    Write-Host "[!] Rien a backuper (aucun chemin trouve)" -ForegroundColor Yellow
    exit 0
}

& $restic backup @backupPaths --tag hub --tag (Get-Date -Format 'yyyy-MM-dd')
$rc = $LASTEXITCODE

# Cleanup temp dump
Remove-Item $tempDumpDir -Recurse -Force -ErrorAction SilentlyContinue

if ($rc -eq 0) {
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "[OK] Backup termine" -ForegroundColor Green
        Write-Host ""
        Write-Host "Pour lister les snapshots:" -ForegroundColor White
        Write-Host "  `$env:RESTIC_REPOSITORY='$resticRepo'; `$env:RESTIC_PASSWORD='...'; restic snapshots" -ForegroundColor DarkGray
        Write-Host "Pour restore:" -ForegroundColor White
        Write-Host "  restic restore latest --target C:\restore" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[X] Backup echoue (exit=$rc)" -ForegroundColor Red
}

exit $rc
