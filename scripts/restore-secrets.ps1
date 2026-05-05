# restore-secrets.ps1
# ===================
# Restaure les secrets sur l'autre PC depuis le bundle chiffre genere par
# bundle-secrets.ps1
#
# Usage (sur l'autre PC apres avoir clone les repos depuis GitHub) :
#   .\restore-secrets.ps1 -Bundle C:\Users\xxx\Downloads\hub-secrets-bundle.zip

param(
    [Parameter(Mandatory=$true)]
    [string]$Bundle
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Bundle)) {
    Write-Host "ERROR: bundle introuvable : $Bundle" -ForegroundColor Red
    exit 1
}

# Detecte la racine du hub
$candidates = @(
    "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso",
    "C:\hub",
    "$env:USERPROFILE\hub",
    "D:\hub"
)
$root = $null
foreach ($c in $candidates) {
    if (Test-Path "$c\hub-core") { $root = $c; break }
}

if (-not $root) {
    Write-Host "Hub non trouve dans les paths habituels. Specifie manuellement :" -ForegroundColor Yellow
    $root = Read-Host "Path du hub (ex: C:\hub)"
    if (-not (Test-Path "$root\hub-core")) {
        Write-Host "ERROR: $root\hub-core inexistant. Clone d'abord les repos." -ForegroundColor Red
        Write-Host "  cd $root"
        Write-Host "  git clone https://github.com/MoKarade/hub-core"
        Write-Host "  git clone https://github.com/MoKarade/hub-frontend"
        Write-Host "  git clone https://github.com/MoKarade/hub-deploy"
        Write-Host "  git clone https://github.com/MoKarade/hub-ingest"
        Write-Host "  git clone https://github.com/MoKarade/hub-docs"
        exit 1
    }
}

Write-Host "Hub detecte a : $root" -ForegroundColor Cyan

# Trouve 7-Zip
$sevenZip = $null
foreach ($p in @(
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
    "$env:LOCALAPPDATA\Programs\7-Zip\7z.exe"
)) {
    if (Test-Path $p) { $sevenZip = $p; break }
}
if (-not $sevenZip) {
    Write-Host "ERROR: 7-Zip non installe. winget install 7zip.7zip" -ForegroundColor Red
    exit 1
}

# Extract dans un dossier temp
$tempDir = "$env:TEMP\hub-secrets-$(Get-Random)"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

Write-Host ""
$pwd = Read-Host "Master password" -AsSecureString
$pwdPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd)
)

Write-Host "Extraction..." -ForegroundColor Cyan
$null = & $sevenZip x "-p$pwdPlain" "-o$tempDir" $Bundle 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: extraction failed (mauvais password ou bundle corrompu)" -ForegroundColor Red
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    exit 1
}

# Cherche tous les fichiers extraits, en preservant l'arborescence relative
$found = Get-ChildItem -Path $tempDir -Recurse -File

Write-Host ""
Write-Host "Fichiers extraits :" -ForegroundColor Green
foreach ($f in $found) {
    $rel = $f.FullName.Substring($tempDir.Length + 1)
    Write-Host "  - $rel"
}

Write-Host ""
Write-Host "Restauration..." -ForegroundColor Cyan

# Pour chaque fichier extrait, on reconstitue le path destination
# en joignant root + chemin relatif depuis le staging zip
foreach ($f in $found) {
    $rel = $f.FullName.Substring($tempDir.Length + 1)  # ex: "hub-core\.env"
    $dest = Join-Path $root $rel

    $destDir = Split-Path -Parent $dest
    if (-not (Test-Path $destDir)) {
        Write-Host "  ! Dossier parent absent, skip : $dest" -ForegroundColor Yellow
        Write-Host "    (clone d'abord les repos GitHub)" -ForegroundColor DarkYellow
        continue
    }

    # Backup l'existant
    if (Test-Path $dest) {
        $backup = "$dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $dest $backup
        Write-Host "  ~ backup : $backup" -ForegroundColor DarkGray
    }
    Copy-Item $f.FullName $dest -Force
    $size = [math]::Round((Get-Item $dest).Length / 1KB, 1)
    Write-Host "  + $dest ($size KB)" -ForegroundColor Green
}

# Cleanup
Remove-Item -Recurse -Force $tempDir

Write-Host ""
Write-Host "[OK] Restauration terminee." -ForegroundColor Green
Write-Host ""
Write-Host "Prochaines etapes :" -ForegroundColor Cyan
Write-Host "  1. Verifier les .env (cd hub-core; cat .env)"
Write-Host "  2. Lancer alembic : .\.venv\Scripts\python.exe -m alembic upgrade head"
Write-Host "  3. Demarrer la stack : cmd /c C:\hub\start-uvicorn.bat ; cd hub-frontend; npm run dev"
Write-Host ""
Write-Host "ATTENTION : si tu as transfere hub.db, NE PAS lancer alembic upgrade --before-replay"
Write-Host "            (la DB transferee est deja a jour avec toutes tes donnees)"
