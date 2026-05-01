# stop_hub.ps1
# Arrete tout le Personal Data Hub (Docker stack OU uvicorn natif + frontend Next.js).

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "[*] Arret du Personal Data Hub..." -ForegroundColor Cyan
Write-Host ""

function Test-CommandExists($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# 1. Arreter Docker stack si tournait
if (Test-CommandExists "docker") {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        $running = docker ps --filter "name=hub-" --format "{{.Names}}" 2>&1
        if ($running) {
            Write-Host "[*] Arret stack Docker..." -ForegroundColor Yellow
            Push-Location "$PSScriptRoot\.."
            docker compose -f docker-compose.dev.yml down 2>&1 | Out-Null
            Pop-Location
            Write-Host "  [OK] Stack Docker arretee (volumes preserves)" -ForegroundColor Green
        }
    }
}

# 2. Arreter uvicorn natif (hub-core)
$killedHubCore = 0
Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmdLine -match "uvicorn.*src.main:app" -or $cmdLine -match "hub-core") {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killedHubCore++
    }
}
if ($killedHubCore -gt 0) {
    Write-Host "  [OK] $killedHubCore process hub-core (uvicorn natif) tues" -ForegroundColor Green
}

# 3. Arreter frontend Next.js (process node lies a HubFrontend / .next)
$killedFront = 0
Get-Process node -ErrorAction SilentlyContinue | ForEach-Object {
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmdLine -match "next" -or $cmdLine -match "HubFrontend" -or $cmdLine -match "hub-frontend") {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killedFront++
    }
}
if ($killedFront -gt 0) {
    Write-Host "  [OK] $killedFront process frontend (Next.js) tues" -ForegroundColor Green
}

# 4. Optionnel : Ollama reste actif (utile pour autres apps), mentionne si --kill-ollama passe en arg
if ($args -contains "--kill-ollama") {
    Get-Process ollama -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Ollama tue (option --kill-ollama)" -ForegroundColor Green
}

Write-Host ""
Write-Host "[OK] Hub arrete." -ForegroundColor Green
Write-Host "  Ollama reste actif (passe --kill-ollama pour le tuer aussi)" -ForegroundColor DarkGray
Write-Host "  Pour relancer : .\scripts\launch-app.ps1" -ForegroundColor DarkGray
Write-Host ""
