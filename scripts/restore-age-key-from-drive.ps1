# restore-age-key-from-drive.ps1
# Restaure la cle privee age depuis le backup chiffre sur Drive (AES-256 + PBKDF2).
# Utile sur un nouveau PC, ou apres crash disque.

$ErrorActionPreference = "Stop"

$encryptedBackup = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\age-key-BACKUP.enc"
$secretsDir = "C:\Users\$env:USERNAME\.hub-secrets"
$keyFile = "$secretsDir\age-key.txt"

if (-not (Test-Path $encryptedBackup)) {
    Write-Host "[X] Backup introuvable sur Drive: $encryptedBackup" -ForegroundColor Red
    Write-Host "    Lance d'abord backup-age-key-to-drive.ps1 sur l'autre PC." -ForegroundColor Yellow
    exit 1
}

$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    Write-Host "[X] openssl introuvable. Installe Git for Windows." -ForegroundColor Red
    exit 1
}

if (Test-Path $keyFile) {
    Write-Host "[!] Cle existe deja: $keyFile" -ForegroundColor Yellow
    $confirm = Read-Host "Ecraser ? (yes/no)"
    if ($confirm -ne "yes") { exit 0 }
}

if (-not (Test-Path $secretsDir)) {
    New-Item -ItemType Directory -Path $secretsDir | Out-Null
}

Write-Host ""
Write-Host "  Restauration cle age depuis Drive backup" -ForegroundColor Cyan
$sec = Read-Host "Password de dechiffrement" -AsSecureString
$pwd = [System.Net.NetworkCredential]::new("", $sec).Password

& openssl enc -d -aes-256-cbc -pbkdf2 -iter 1000000 `
    -in $encryptedBackup -out $keyFile -pass "pass:$pwd" 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0 -and (Test-Path $keyFile)) {
    Write-Host ""
    Write-Host "  [OK] Cle age restauree: $keyFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Tu peux dechiffrer le vault:" -ForegroundColor White
    Write-Host "    .\scripts\decrypt-vault.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "[X] Restauration echouee (mauvais password ?)" -ForegroundColor Red
    if (Test-Path $keyFile) { Remove-Item $keyFile }
    exit 1
}
