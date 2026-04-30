# backup-age-key-to-drive.ps1
# Backup la cle privee age (qui dechiffre le vault) sur Drive de maniere
# securisee : chiffre avec un password (AES-256-CBC + PBKDF2 1M iterations).
#
# Le fichier .enc sur Drive est inutile sans le password.
# OpenSSL est utilise (vient avec Git for Windows).
#
# Usage: .\scripts\backup-age-key-to-drive.ps1
# Usage script: $env:HUB_BACKUP_PASSWORD="..."; .\scripts\backup-age-key-to-drive.ps1 -Quiet

param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$keyFile = "C:\Users\$env:USERNAME\.hub-secrets\age-key.txt"
$encryptedBackup = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\age-key-BACKUP.enc"

if (-not (Test-Path $keyFile)) {
    Write-Host "[X] Cle age introuvable: $keyFile" -ForegroundColor Red
    exit 1
}

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    Write-Host "[X] openssl introuvable. Installe Git for Windows (qui inclut openssl)." -ForegroundColor Red
    exit 1
}

# Get password
$pwd = $env:HUB_BACKUP_PASSWORD
if (-not $pwd) {
    if ($Quiet) {
        Write-Host "[X] HUB_BACKUP_PASSWORD env var requise en mode -Quiet" -ForegroundColor Red
        exit 1
    }
    Write-Host ""
    Write-Host "  Backup chiffre de la cle age vers Drive" -ForegroundColor Cyan
    Write-Host ""
    $sec = Read-Host "Password de chiffrement" -AsSecureString
    $pwd = [System.Net.NetworkCredential]::new("", $sec).Password
    $sec2 = Read-Host "Confirme password" -AsSecureString
    $pwd2 = [System.Net.NetworkCredential]::new("", $sec2).Password
    if ($pwd -ne $pwd2) {
        Write-Host "[X] Passwords ne matchent pas" -ForegroundColor Red
        exit 1
    }
}

# AES-256-CBC + PBKDF2 (1M iterations) + salt aleatoire
& openssl enc -aes-256-cbc -salt -pbkdf2 -iter 1000000 `
    -in $keyFile -out $encryptedBackup -pass "pass:$pwd" 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0 -and (Test-Path $encryptedBackup)) {
    $info = Get-Item $encryptedBackup
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "  [OK] Backup cree: $encryptedBackup" -ForegroundColor Green
        Write-Host "       Taille: $($info.Length) bytes" -ForegroundColor DarkGray
        Write-Host "       Algo: AES-256-CBC + PBKDF2 (1M iterations)" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Drive sync ce fichier automatiquement -> backup multi-PC" -ForegroundColor White
        Write-Host ""
        Write-Host "  Pour restaurer (si tu perds la cle locale):" -ForegroundColor White
        Write-Host "    .\scripts\restore-age-key-from-drive.ps1" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[X] Echec chiffrement" -ForegroundColor Red
    exit 1
}
