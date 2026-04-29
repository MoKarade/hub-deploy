# verify.ps1
# Vérifie l'intégrité du repo restic (checksum + cohérence).
# À lancer mensuellement (cf. ADR-0006).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$ReadData,  # check approfondi (lit toute la data — peut prendre longtemps)

    [Parameter(Mandatory = $false)]
    [string]$AgeKeyPath = "$env:USERPROFILE\.age\hub.key",

    [Parameter(Mandatory = $false)]
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

Write-Host "[*] Hub backup verify" -ForegroundColor Cyan

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

Write-Host "[*] Liste des snapshots :" -ForegroundColor Cyan
restic snapshots

Write-Host ""
Write-Host "[*] restic check ..." -ForegroundColor Cyan
if ($ReadData) {
    restic check --read-data
} else {
    restic check
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "[OK] Repo intègre" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[X] Repo corrompu — voir backup/README.md troubleshooting" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[*] restic stats :" -ForegroundColor Cyan
restic stats latest
