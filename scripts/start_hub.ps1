# start_hub.ps1
# Demarre la stack du Personal Data Hub en mode dev.

$ErrorActionPreference = "Stop"

Write-Host "[*] Demarrage du Personal Data Hub..." -ForegroundColor Cyan

# 1. Verifie que Docker Desktop tourne
$dockerStatus = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[X] Docker Desktop ne semble pas demarre." -ForegroundColor Red
    Write-Host "Lance Docker Desktop puis relance ce script." -ForegroundColor Yellow
    exit 1
}

# 2. Verifie qu'Ollama tourne
$ollamaStatus = curl http://localhost:11434/api/tags -UseBasicParsing -ErrorAction SilentlyContinue
if (-not $ollamaStatus) {
    Write-Host "[*] Ollama ne semble pas demarre. Lancement..." -ForegroundColor Yellow
    Start-Process -FilePath "ollama" -ArgumentList "serve" -NoNewWindow
    Start-Sleep -Seconds 3
}

# 3. Verifie que les modeles Ollama sont pull
$models = ollama list 2>&1
if (-not ($models -match "qwen2.5:14b-instruct")) {
    Write-Host "[*] Modele qwen2.5:14b-instruct manquant. Pull en cours..." -ForegroundColor Yellow
    ollama pull qwen2.5:14b-instruct
}
if (-not ($models -match "nomic-embed-text")) {
    Write-Host "[*] Modele nomic-embed-text manquant. Pull en cours..." -ForegroundColor Yellow
    ollama pull nomic-embed-text
}

# 4. Lance la stack docker-compose
Write-Host "[*] docker compose up..." -ForegroundColor Cyan
Push-Location $PSScriptRoot\..
docker compose -f docker-compose.dev.yml up -d --build
Pop-Location

# 5. Healthcheck
Write-Host "[*] Attente que tout soit healthy..." -ForegroundColor Cyan
$maxRetries = 30
$retry = 0
while ($retry -lt $maxRetries) {
    Start-Sleep -Seconds 2
    $health = curl http://localhost:8000/v1/health -UseBasicParsing -ErrorAction SilentlyContinue
    if ($health.StatusCode -eq 200) {
        Write-Host "[OK] Hub up et healthy!" -ForegroundColor Green
        break
    }
    $retry++
    Write-Host "  ($retry/$maxRetries) ..."
}

if ($retry -eq $maxRetries) {
    Write-Host "[X] Timeout. Verifie 'docker compose logs hub-core'" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[*] Personal Data Hub disponible :" -ForegroundColor Green
Write-Host "  - API     : http://localhost:8000" -ForegroundColor White
Write-Host "  - Docs    : http://localhost:8000/docs" -ForegroundColor White
Write-Host "  - Health  : http://localhost:8000/v1/health" -ForegroundColor White
Write-Host "  - Ready   : http://localhost:8000/v1/ready (DB + Ollama)" -ForegroundColor White
Write-Host ""
Write-Host "Pour arreter : .\scripts\stop_hub.ps1" -ForegroundColor Gray
