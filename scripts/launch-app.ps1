# launch-app.ps1
# Lance le Personal Data Hub comme une vraie app sur le PC.
# Demarre tout (Docker, Ollama, frontend) puis ouvre Chrome en mode app.

$ErrorActionPreference = "Stop"

function Test-CommandExists($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Wait-ForUrl($url, $maxRetries = 30, $delay = 2) {
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
            if ($r.StatusCode -eq 200) { return $true }
        } catch {
            # ignore
        }
        Start-Sleep -Seconds $delay
        Write-Host "  ($i/$maxRetries) en attente de $url..." -ForegroundColor DarkGray
    }
    return $false
}

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host "    Personal Data Hub - Launch as App" -ForegroundColor Green
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host ""

# 1. Demarrer Ollama si necessaire
Write-Host "[*] Verification Ollama..." -ForegroundColor Cyan
$ollamaProc = Get-Process ollama -ErrorAction SilentlyContinue
if (-not $ollamaProc) {
    $ollamaPath = "C:\Users\$env:USERNAME\AppData\Local\Programs\Ollama\ollama.exe"
    if (-not (Test-Path $ollamaPath)) {
        $cmd = Get-Command ollama -ErrorAction SilentlyContinue
        if ($cmd) { $ollamaPath = $cmd.Source }
    }
    if ($ollamaPath -and (Test-Path $ollamaPath)) {
        Write-Host "  Demarrage Ollama daemon..." -ForegroundColor Yellow
        Start-Process -FilePath $ollamaPath -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
        Write-Host "  [OK] Ollama demarre" -ForegroundColor Green
    } else {
        Write-Host "  [!] Ollama non installe. Skip (frontend marchera mais sans IA)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  [OK] Ollama deja actif (PID: $($ollamaProc.Id))" -ForegroundColor Green
}

# 2. Demarrer Docker stack si Docker installe
Write-Host ""
Write-Host "[*] Verification Docker..." -ForegroundColor Cyan
if (Test-CommandExists "docker") {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Docker en marche" -ForegroundColor Green
        $hubCoreUp = docker ps --filter "name=hub-dev-hub-core" --format "{{.Names}}" 2>&1
        if (-not $hubCoreUp) {
            Write-Host "  Demarrage de la stack docker..." -ForegroundColor Yellow
            Push-Location "$PSScriptRoot\.."
            docker compose -f docker-compose.dev.yml up -d 2>&1 | Out-Null
            Pop-Location
            Write-Host "  Attente du healthcheck hub-core..." -ForegroundColor Yellow
            if (Wait-ForUrl "http://localhost:8000/v1/health" 30 2) {
                Write-Host "  [OK] hub-core healthy" -ForegroundColor Green
            } else {
                Write-Host "  [!] hub-core ne repond pas. Verifie 'docker compose logs'" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  [OK] hub-core deja actif" -ForegroundColor Green
        }
    } else {
        Write-Host "  [!] Docker installe mais pas demarre. Lance Docker Desktop d'abord." -ForegroundColor Yellow
    }
} else {
    Write-Host "  [!] Docker pas installe. Frontend marchera sans hub-core." -ForegroundColor Yellow
}

# 3. Demarrer le frontend
Write-Host ""
Write-Host "[*] Verification frontend..." -ForegroundColor Cyan
$frontendUp = $false
try {
    $r = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    if ($r.StatusCode -eq 200) {
        $frontendUp = $true
        Write-Host "  [OK] Frontend deja actif" -ForegroundColor Green
    }
} catch {
    # not running
}

if (-not $frontendUp) {
    $candidates = @(
        "C:\HubFrontend",
        "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-frontend"
    )
    $frontendDir = $null
    foreach ($c in $candidates) {
        if (Test-Path "$c\package.json") {
            $frontendDir = $c
            break
        }
    }

    if ($frontendDir) {
        Write-Host "  Demarrage frontend depuis $frontendDir..." -ForegroundColor Yellow
        $nodePath = (Get-Command node).Source
        $nextPath = "$frontendDir\node_modules\next\dist\bin\next"
        if (Test-Path $nextPath) {
            Start-Process -FilePath $nodePath -ArgumentList $nextPath, "dev" -WorkingDirectory $frontendDir -WindowStyle Hidden
        } else {
            Write-Host "  [X] node_modules manquant dans $frontendDir. Lance 'npm install'." -ForegroundColor Red
            exit 1
        }

        Write-Host "  Attente du frontend..." -ForegroundColor Yellow
        if (Wait-ForUrl "http://localhost:3000" 30 2) {
            Write-Host "  [OK] Frontend ready" -ForegroundColor Green
            $frontendUp = $true
        } else {
            Write-Host "  [X] Frontend timeout. Verifie les logs." -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  [X] Pas trouve hub-frontend dans C:\HubFrontend ou G:\..." -ForegroundColor Red
        exit 1
    }
}

# 4. Ouvrir Chrome en mode app
Write-Host ""
Write-Host "[*] Ouverture du Hub en mode app..." -ForegroundColor Cyan

$chromeCandidates = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    "C:\Users\$env:USERNAME\AppData\Local\Google\Chrome\Application\chrome.exe"
)
$edgeCandidates = @(
    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
)

$browser = $null
foreach ($c in $chromeCandidates) {
    if (Test-Path $c) { $browser = $c; break }
}
if (-not $browser) {
    foreach ($c in $edgeCandidates) {
        if (Test-Path $c) { $browser = $c; break }
    }
}

if ($browser) {
    Start-Process -FilePath $browser -ArgumentList @(
        "--app=http://localhost:3000",
        "--window-size=1400,900",
        "--disable-features=TranslateUI",
        "--no-default-browser-check",
        "--no-first-run"
    )
    Write-Host "  [OK] Hub perso ouvert comme app !" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Tu peux fermer ce terminal, l app reste ouverte." -ForegroundColor DarkGray
    Write-Host "  Pour arreter le hub : .\scripts\stop_hub.ps1" -ForegroundColor DarkGray
} else {
    Write-Host "  [!] Chrome/Edge pas trouve. Ouvre manuellement http://localhost:3000" -ForegroundColor Yellow
    Start-Process "http://localhost:3000"
}

Write-Host ""
