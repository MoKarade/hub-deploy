# restore.ps1
# Restore d'un snapshot restic vers un dossier cible.
# Par défaut, snapshot = latest.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $false)]
    [string]$Snapshot = "latest",

    [Parameter(Mandatory = $false)]
    [string]$AgeKeyPath = "$env:USERPROFILE\.age\hub.key",

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

Write-Host "[*] Hub restore - snapshot=$Snapshot target=$Target" -ForegroundColor Cyan

# ----------------------------------------------------------------------
# Charge les credentials restic depuis sops
# ----------------------------------------------------------------------
$secretsPath = Join-Path $RepoRoot "secrets\restic.enc.yaml"
if (-not (Test-Path $secretsPath)) {
    Write-Host "[X] Manquant : $secretsPath" -ForegroundColor Red
    exit 1
}

$env:SOPS_AGE_KEY_FILE = $AgeKeyPath
$resticConfig = sops --decrypt $secretsPath | Out-String
foreach ($line in $resticConfig -split "`n") {
    if ($line -match "^RESTIC_PASSWORD:\s*(.+)$") { $env:RESTIC_PASSWORD = $matches[1].Trim() }
    if ($line -match "^RESTIC_REPOSITORY:\s*(.+)$") { $env:RESTIC_REPOSITORY = $matches[1].Trim() }
}

# ----------------------------------------------------------------------
# Restore
# ----------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $Target | Out-Null

Write-Host "[*] restic restore $Snapshot --target $Target ..." -ForegroundColor Cyan
restic restore $Snapshot --target $Target
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Restore a échoué" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[OK] Restore terminé : $Target" -ForegroundColor Green
Write-Host ""
Write-Host "Pour restaurer la DB :" -ForegroundColor Cyan
Write-Host "  docker exec -i <postgres-container> psql -U hub hubdb < $Target\db.sql" -ForegroundColor White
Write-Host ""
Write-Host "Pour restaurer les raw_events :" -ForegroundColor Cyan
Write-Host "  Copy-Item -Recurse $Target\raw_events C:\hub\raw_events" -ForegroundColor White
