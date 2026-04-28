# setup_windows.ps1
# Setup initial du Personal Data Hub sur Windows.
# A lancer 1 fois apres avoir clone les repos.

$ErrorActionPreference = "Stop"

Write-Host "[*] Personal Data Hub - setup Windows" -ForegroundColor Cyan
Write-Host ""

function Test-CommandExists($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# 1. Check des prerequis
Write-Host "[*] Verification des prerequis..." -ForegroundColor Cyan
$missing = @()

if (-not (Test-CommandExists "docker")) { $missing += "Docker Desktop (winget install Docker.DockerDesktop)" }
if (-not (Test-CommandExists "ollama")) { $missing += "Ollama (winget install Ollama.Ollama)" }
if (-not (Test-CommandExists "git")) { $missing += "Git (winget install Git.Git)" }
if (-not (Test-CommandExists "age-keygen")) { $missing += "age (winget install FiloSottile.age)" }
if (-not (Test-CommandExists "sops")) { $missing += "sops (winget install Mozilla.sops)" }

if ($missing.Count -gt 0) {
    Write-Host "[X] Outils manquants :" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    Write-Host "Installe-les puis relance ce script." -ForegroundColor Yellow
    exit 1
}
Write-Host "  [OK] Tous les prerequis sont installes" -ForegroundColor Green

# 2. .env
Write-Host ""
Write-Host "[*] Configuration .env..." -ForegroundColor Cyan
$envPath = Join-Path $PSScriptRoot "..\.env"
$envExamplePath = Join-Path $PSScriptRoot "..\.env.example"
if (-not (Test-Path $envPath)) {
    Copy-Item $envExamplePath $envPath
    Write-Host "  [OK] .env cree depuis .env.example" -ForegroundColor Green
    Write-Host "  [!] Edite $envPath et remplis les valeurs avant de continuer" -ForegroundColor Yellow
} else {
    Write-Host "  [OK] .env existe deja (pas ecrase)" -ForegroundColor Green
}

# 3. Verification de la GPU NVIDIA pour Ollama
Write-Host ""
Write-Host "[*] Verification GPU NVIDIA..." -ForegroundColor Cyan
$nvidia = nvidia-smi 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] GPU NVIDIA detectee - Ollama va l'utiliser" -ForegroundColor Green
} else {
    Write-Host "  [!] Pas de GPU NVIDIA detectee - Ollama tournera en CPU (lent)" -ForegroundColor Yellow
}

# 4. Pull des modeles Ollama
Write-Host ""
Write-Host "[*] Pull des modeles Ollama (peut prendre 5-15 min)..." -ForegroundColor Cyan
ollama pull qwen2.5:14b-instruct
ollama pull nomic-embed-text

Write-Host ""
Write-Host "[OK] Setup termine" -ForegroundColor Green
Write-Host ""
Write-Host "Prochaines etapes :" -ForegroundColor Cyan
Write-Host "  1. Edite $envPath" -ForegroundColor White
Write-Host "  2. Genere ta cle age : age-keygen -o `$env:USERPROFILE\.age\hub.key" -ForegroundColor White
Write-Host "  3. Lance le hub : .\scripts\start_hub.ps1" -ForegroundColor White
