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

# 2. Arreter uvicorn natif (hub-core). Filtre strict : on cible uniquement
# les python du venv hub-core ou dont la CommandLine reference hub-core.
# Evite de tuer un python d'un autre projet sur la machine.
$killedHubCore = 0
Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match "uvicorn" -and $_.CommandLine -match "src\.main:app" -and
    ($_.ExecutablePath -like "*\hub-core\.venv\*" -or $_.CommandLine -like "*hub-core*")
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    $killedHubCore++
}
if ($killedHubCore -gt 0) {
    Write-Host "  [OK] $killedHubCore process hub-core (uvicorn natif) tues" -ForegroundColor Green
}

# 3. Arreter frontend Next.js. Filtre strict : "next" + dossier hub-frontend.
# Evite de tuer un autre node sur la machine.
$killedFront = 0
Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match "next" -and
    ($_.CommandLine -like "*HubFrontend*" -or $_.CommandLine -like "*hub-frontend*")
} | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    $killedFront++
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
