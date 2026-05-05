# bundle-secrets.ps1
# ===================
# Zip tous les fichiers sensibles du hub dans une archive chiffree pour transfert
# vers un autre PC.
#
# Usage:
#   .\bundle-secrets.ps1                          # cree secrets-bundle.zip dans Downloads
#   .\bundle-secrets.ps1 -Output C:\bundle.zip    # path custom
#   .\bundle-secrets.ps1 -SkipDb                  # exclure la DB SQLite (101 MB)
#
# Pour decrypter sur l'autre PC :
#   1. Copier secrets-bundle.zip via USB / cloud / etc.
#   2. Extraire avec 7zip (te demandera le password)
#   3. Restaurer chaque .env a sa place
#   4. Restaurer hub.db dans hub-core/
#
# IMPORTANT : ne JAMAIS commit ce zip ni le mettre sur Drive sans verifier
# le chiffrement. Le master password n'est ecrit nulle part dans le code.

param(
    [string]$Output = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\_transfer\hub-secrets-bundle.7z",
    [switch]$SkipDb,
    [switch]$IncludeDb
)

# Cree le dossier _transfer dans Drive si inexistant (synced auto entre les 2 PCs)
$outputDir = Split-Path -Parent $Output
if (-not (Test-Path $outputDir)) { New-Item -ItemType Directory -Force -Path $outputDir | Out-Null }

$ErrorActionPreference = "Stop"
$root = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso"

if (-not (Test-Path $root)) {
    Write-Host "ERROR: project root not found at $root" -ForegroundColor Red
    exit 1
}

# Inventaire des secrets
$secrets = @(
    "$root\hub-core\.env",
    "$root\hub-deploy\.env",
    "$root\hub-frontend\.env.local",
    "$root\age-key-BACKUP.enc"
)

$missing = @()
$existing = @()
foreach ($f in $secrets) {
    if (Test-Path $f) { $existing += $f }
    else { $missing += $f }
}

if ($missing.Count -gt 0) {
    Write-Host "Fichiers manquants (ignores) :" -ForegroundColor Yellow
    foreach ($f in $missing) { Write-Host "  - $f" -ForegroundColor DarkYellow }
}

# La DB SQLite contient TOUS les OAuth tokens + 13k visites + emails + finance
# Marc peut choisir de l'inclure (101 MB) ou pas
$dbPath = "$root\hub-core\hub.db"
$includeDbFinal = $false
if ((Test-Path $dbPath) -and -not $SkipDb) {
    $dbSize = [math]::Round((Get-Item $dbPath).Length / 1MB, 1)
    if ($IncludeDb) {
        $includeDbFinal = $true
    } else {
        Write-Host ""
        Write-Host "DB SQLite trouvee : $dbPath ($dbSize MB)" -ForegroundColor Cyan
        Write-Host "Elle contient : OAuth tokens chiffres + 13k visites + 470 transactions + emails sync"
        $resp = Read-Host "L'inclure dans le bundle ? (yes/no)"
        if ($resp -match "^(y|yes|o|oui)$") { $includeDbFinal = $true }
    }
    if ($includeDbFinal) { $existing += $dbPath }
}

Write-Host ""
Write-Host "Fichiers a bundler :" -ForegroundColor Green
foreach ($f in $existing) {
    $size = [math]::Round((Get-Item $f).Length / 1KB, 1)
    Write-Host "  + $f ($size KB)"
}

if ($existing.Count -eq 0) {
    Write-Host "Aucun fichier a bundler. Aborting." -ForegroundColor Red
    exit 1
}

Write-Host ""
$pwd = Read-Host "Master password (sera demande pour dechiffrer le zip)" -AsSecureString
$pwdPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd)
)

if ([string]::IsNullOrWhiteSpace($pwdPlain)) {
    Write-Host "ERROR: password vide refuse" -ForegroundColor Red
    exit 1
}

# Trouve 7-Zip (requis pour AES-256 password protection)
$sevenZip = $null
foreach ($p in @(
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
    "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
)) {
    if (Test-Path $p) { $sevenZip = $p; break }
}

if (-not $sevenZip) {
    Write-Host "ERROR: 7-Zip non trouve. Installe-le depuis https://7-zip.org" -ForegroundColor Red
    Write-Host "Ou utilise winget : winget install 7zip.7zip" -ForegroundColor Yellow
    exit 1
}

# Cleanup output existant
if (Test-Path $Output) { Remove-Item $Output -Force }

# Staging dir avec arborescence (sinon 7z refuse les .env doublons)
$staging = "$env:TEMP\hub-secrets-staging-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $staging | Out-Null

foreach ($f in $existing) {
    # Reconstruit la structure relative au root
    $rel = $f.Substring($root.Length + 1)  # ex: "hub-core\.env"
    $dest = Join-Path $staging $rel
    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Force -Path $destDir | Out-Null }
    Copy-Item $f $dest -Force
}

# Zip le staging avec password (AES-256, headers chiffres -mhe)
Write-Host ""
Write-Host "Creation du bundle chiffre..." -ForegroundColor Cyan
Push-Location $staging
$null = & $sevenZip a -t7z "-p$pwdPlain" "-mhe=on" "-mx=5" $Output "*" 2>&1
$sevenZipExit = $LASTEXITCODE
Pop-Location

# Cleanup staging meme en cas d'erreur
Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue

if ($sevenZipExit -ne 0) {
    Write-Host "ERROR: 7zip failed (exit $sevenZipExit)" -ForegroundColor Red
    exit 1
}

$bundleSize = [math]::Round((Get-Item $Output).Length / 1MB, 1)
Write-Host ""
Write-Host "[OK] Bundle chiffre cree :" -ForegroundColor Green
Write-Host "     $Output ($bundleSize MB)" -ForegroundColor White
Write-Host ""
Write-Host "Pour transferer sur l'autre PC :" -ForegroundColor Cyan
Write-Host "  1. Copier $Output via USB / cloud / Bitwarden Send / etc."
Write-Host "  2. Sur l'autre PC, extraire avec 7-Zip (entrer le master password)"
Write-Host "  3. Restaurer chaque .env a sa place dans le hub"
if ($includeDbFinal) {
    Write-Host "  4. Restaurer hub.db dans hub-core/ (PRESERVE les 13k visites + tokens OAuth)"
}
Write-Host ""
Write-Host "Securite :" -ForegroundColor Yellow
Write-Host "  - Le zip est chiffre AES-256 avec headers chiffres (-mhe)"
Write-Host "  - Sans le password, impossible de meme voir les noms de fichiers"
Write-Host "  - Le password est ton master (cf. memory secrets_api_keys.md)"
Write-Host "  - NE PAS commit ce zip dans git, NE PAS le mettre sur Drive sans password"
