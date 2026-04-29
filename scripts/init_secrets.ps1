# init_secrets.ps1
# Bootstrap initial du vault age + sops.
# Idempotent : ne ré-écrase rien si la clé existe déjà.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$AgeKeyPath = "$env:USERPROFILE\.age\hub.key"
)

$ErrorActionPreference = "Stop"

Write-Host "[*] Personal Data Hub - init secrets vault" -ForegroundColor Cyan
Write-Host ""

function Test-CommandExists($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# 1. Vérifie age + sops
$missing = @()
if (-not (Test-CommandExists "age-keygen")) { $missing += "age (winget install FiloSottile.age)" }
if (-not (Test-CommandExists "sops")) { $missing += "sops (winget install Mozilla.sops)" }
if ($missing.Count -gt 0) {
    Write-Host "[X] Outils manquants :" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" }
    exit 1
}

# 2. Génère la clé age si elle n'existe pas
$ageKeyDir = Split-Path $AgeKeyPath -Parent
if (-not (Test-Path $ageKeyDir)) {
    Write-Host "[*] Création $ageKeyDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $ageKeyDir | Out-Null
}

if (Test-Path $AgeKeyPath) {
    Write-Host "[OK] Clé age existante à $AgeKeyPath" -ForegroundColor Green
} else {
    Write-Host "[*] Génération de la clé age..." -ForegroundColor Cyan
    age-keygen -o $AgeKeyPath
    Write-Host "[OK] Clé générée à $AgeKeyPath" -ForegroundColor Green
}

# 3. Affiche la public key
$pubkey = age-keygen -y $AgeKeyPath
Write-Host ""
Write-Host "[*] Public key :" -ForegroundColor Cyan
Write-Host "    $pubkey" -ForegroundColor White

# 4. Vérifie .sops.yaml
$sopsConfigPath = Join-Path $PSScriptRoot "..\.sops.yaml"
if (Test-Path $sopsConfigPath) {
    $content = Get-Content $sopsConfigPath -Raw
    if ($content -match "REPLACE_WITH_YOUR_AGE_PUBLIC_KEY") {
        Write-Host ""
        Write-Host "[!] .sops.yaml contient encore le placeholder." -ForegroundColor Yellow
        Write-Host "    Remplace REPLACE_WITH_YOUR_AGE_PUBLIC_KEY par : $pubkey" -ForegroundColor Yellow
        Write-Host ""
        $reply = Read-Host "Veux-tu que je le remplace automatiquement ? (o/N)"
        if ($reply -eq "o" -or $reply -eq "O") {
            $newContent = $content -replace "REPLACE_WITH_YOUR_AGE_PUBLIC_KEY", $pubkey
            Set-Content -Path $sopsConfigPath -Value $newContent -Encoding utf8 -NoNewline
            Write-Host "[OK] .sops.yaml mis à jour." -ForegroundColor Green
        }
    } else {
        Write-Host "[OK] .sops.yaml déjà configuré" -ForegroundColor Green
    }
} else {
    Write-Host "[X] .sops.yaml manquant à $sopsConfigPath" -ForegroundColor Red
    exit 1
}

# 5. Reminders critiques
Write-Host ""
Write-Host "==============================================================" -ForegroundColor Yellow
Write-Host "[!] CRITIQUE : sauvegarde la clé privée hors du PC !" -ForegroundColor Yellow
Write-Host "==============================================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  La clé privée à : $AgeKeyPath" -ForegroundColor White
Write-Host "  Sans elle, AUCUN backup restic n'est récupérable."
Write-Host ""
Write-Host "  -> Copie-la sur 2 clés USB physiques (cf. ADR-0006) :"
Write-Host "       1. Une chez toi (tiroir bureau)"
Write-Host "       2. Une chez tes parents (geo-redondance)"
Write-Host ""
Write-Host "  -> JAMAIS sur OneDrive, Google Drive, GitHub, etc."
Write-Host ""

Write-Host "[OK] Setup secrets terminé." -ForegroundColor Green
Write-Host ""
Write-Host "Prochaines étapes :" -ForegroundColor Cyan
Write-Host "  1. Sauvegarde la clé sur 2 USB"
Write-Host "  2. Crée tes premiers secrets : sops secrets/postgres.enc.yaml"
Write-Host "  3. Documente tes secrets : voir secrets/README.md"
