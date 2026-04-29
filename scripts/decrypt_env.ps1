# decrypt_env.ps1
# Déchiffre un secret sops vers stdout.
#
# Usage :
#   .\scripts\decrypt_env.ps1 secrets/postgres.enc.yaml
#   .\scripts\decrypt_env.ps1 secrets/postgres.enc.yaml | Out-File .env.local

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$EncryptedPath,

    [Parameter(Mandatory = $false)]
    [string]$AgeKeyPath = "$env:USERPROFILE\.age\hub.key"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $EncryptedPath)) {
    Write-Host "[X] Fichier introuvable : $EncryptedPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $AgeKeyPath)) {
    Write-Host "[X] Clé age introuvable : $AgeKeyPath" -ForegroundColor Red
    Write-Host "    Restaure-la depuis ta clé USB de backup." -ForegroundColor Yellow
    exit 1
}

$env:SOPS_AGE_KEY_FILE = $AgeKeyPath
sops --decrypt $EncryptedPath
