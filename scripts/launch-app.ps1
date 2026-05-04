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

function Start-HubCoreNative {
    # Demarre hub-core via uvicorn natif (mode SQLite local, pas de Docker requis).
    # Utilise le venv .venv dans hub-core. Si absent, le cree avec uv.
    $candidates = @(
        "C:\HubCore",
        "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-core"
    )
    $hubCoreDir = $null
    foreach ($c in $candidates) {
        if (Test-Path "$c\pyproject.toml") {
            $hubCoreDir = $c
            break
        }
    }
    if (-not $hubCoreDir) {
        Write-Host "  [X] hub-core introuvable" -ForegroundColor Red
        return $false
    }

    # Setup venv si absent
    $py = "$hubCoreDir\.venv\Scripts\python.exe"
    if (-not (Test-Path $py)) {
        Write-Host "  Setup venv hub-core (premier lancement)..." -ForegroundColor Yellow
        Push-Location $hubCoreDir
        & uv venv --python 3.13 2>&1 | Out-Null
        & uv pip install -e ".[dev]" 2>&1 | Out-Null
        Pop-Location
    }

    # Init/migrate SQLite a CHAQUE lancement (idempotent : create_all + auto_migrate
    # qui ALTER TABLE ADD COLUMN pour les colonnes manquantes des modeles).
    # Evite les crashes "no such column: photos.X" quand on pull une nouvelle version.
    if (Test-Path "$hubCoreDir\init_sqlite.py") {
        Write-Host "  Migrate SQLite DB..." -ForegroundColor Yellow
        Push-Location $hubCoreDir
        & $py init_sqlite.py 2>&1 | Out-Null
        Pop-Location
    }

    # Lance uvicorn en background, log redirige vers fichier
    # Note : on utilise $cmdArgs (pas $args qui est reserve par PowerShell pour
    # les arguments du script lui-meme).
    $logFile = "$env:LOCALAPPDATA\hub-core.log"
    $cmdArgs = @("-m", "uvicorn", "src.main:app", "--port", "8000", "--host", "127.0.0.1")
    Start-Process -FilePath $py -ArgumentList $cmdArgs -WorkingDirectory $hubCoreDir `
        -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"

    if (Wait-ForUrl "http://localhost:8000/v1/health" 20 1) {
        Write-Host "  [OK] hub-core natif demarre (SQLite, log: $logFile)" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [X] hub-core natif timeout. Check log: $logFile" -ForegroundColor Red
        return $false
    }
}

function Start-HubCoreWatchdog {
    # Spawn un watchdog en background qui auto-restart hub-core s'il crashe.
    # Retourne le PID pour pouvoir le killer a la fermeture.
    $watchdogScript = Join-Path $PSScriptRoot "hub-core-watchdog.ps1"
    if (-not (Test-Path $watchdogScript)) {
        return $null
    }
    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$watchdogScript`"") `
        -WindowStyle Hidden -PassThru
    Write-Host "  [OK] Watchdog hub-core demarre (PID $($proc.Id))" -ForegroundColor Green
    return $proc.Id
}

function Sync-DriveToCache {
    # Auto-sync Drive (G:\) -> C:\HubFrontend si Drive est plus recent.
    # Evite "j'ai edit sur Drive mais le launch utilise C:\ donc mes changes apparaissent pas"
    $driveDir = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-frontend"
    $cacheDir = "C:\HubFrontend"
    if (-not (Test-Path $driveDir) -or -not (Test-Path $cacheDir)) { return }

    # Compare timestamps des fichiers source (app/, components/, lib/)
    $driveLatest = Get-ChildItem -Path "$driveDir\app", "$driveDir\components", "$driveDir\lib" `
        -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.tsx','.ts','.css') } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $cacheLatest = Get-ChildItem -Path "$cacheDir\app", "$cacheDir\components", "$cacheDir\lib" `
        -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.tsx','.ts','.css') } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($driveLatest -and $cacheLatest -and $driveLatest.LastWriteTime -gt $cacheLatest.LastWriteTime) {
        Write-Host "  Drive plus recent que C:\HubFrontend, sync en cours..." -ForegroundColor Yellow
        # robocopy app/ components/ lib/ (skip node_modules + .next)
        foreach ($d in @('app', 'components', 'lib', 'public', 'styles')) {
            if (Test-Path "$driveDir\$d") {
                & robocopy "$driveDir\$d" "$cacheDir\$d" /MIR /XD node_modules .next /NJH /NJS /NDL /NC /NS /NP 2>&1 | Out-Null
            }
        }
        # Aussi les fichiers config racine importants
        foreach ($f in @('package.json', 'tsconfig.json', 'next.config.ts', 'tailwind.config.ts', 'postcss.config.mjs', 'middleware.ts')) {
            if (Test-Path "$driveDir\$f") {
                Copy-Item "$driveDir\$f" "$cacheDir\$f" -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "  [OK] Sync Drive -> C:\HubFrontend complete" -ForegroundColor Green
    }
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

# 2. Demarrer hub-core (Docker stack si dispo, sinon uvicorn natif avec SQLite)
Write-Host ""
Write-Host "[*] Verification hub-core..." -ForegroundColor Cyan

# D'abord check si hub-core repond deja
$hubCoreAlreadyUp = $false
try {
    $r = Invoke-WebRequest "http://localhost:8000/v1/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
    if ($r.StatusCode -eq 200) {
        Write-Host "  [OK] hub-core deja actif" -ForegroundColor Green
        $hubCoreAlreadyUp = $true
    }
} catch {
    # not running
}

if (-not $hubCoreAlreadyUp) {
    if (Test-CommandExists "docker") {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Docker dispo, stack Postgres..." -ForegroundColor Yellow
            Push-Location "$PSScriptRoot\.."
            docker compose -f docker-compose.dev.yml up -d 2>&1 | Out-Null
            Pop-Location
            if (Wait-ForUrl "http://localhost:8000/v1/health" 30 2) {
                Write-Host "  [OK] hub-core healthy (Docker, Postgres+pgvector)" -ForegroundColor Green
            } else {
                Write-Host "  [!] hub-core Docker ne repond pas. Fallback natif..." -ForegroundColor Yellow
                Start-HubCoreNative | Out-Null
            }
        } else {
            Write-Host "  Docker present mais arrete. Demarrage uvicorn natif..." -ForegroundColor Yellow
            Start-HubCoreNative | Out-Null
        }
    } else {
        Write-Host "  Docker absent. Demarrage uvicorn natif (SQLite local)..." -ForegroundColor Yellow
        Start-HubCoreNative | Out-Null
    }
}

# 2c. Demarre le watchdog qui auto-restart hub-core en cas de crash
$watchdogPid = Start-HubCoreWatchdog

# 2b. Auto-sync Drive -> C:\HubFrontend (frontend cache)
Sync-DriveToCache

# 3. Demarrer le frontend
Write-Host ""
Write-Host "[*] Verification frontend..." -ForegroundColor Cyan
$frontendUp = $false
try {
    $r = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
    if ($r.StatusCode -eq 200) {
        $frontendUp = $true
        Write-Host "  [OK] Frontend deja actif (pas de double lancement)" -ForegroundColor Green
    }
} catch {
    # not running, but check for orphan node processes that didn't bind to :3000.
    # On filtre strictement : il faut "next" ET ("HubFrontend" OU "hub-frontend")
    # pour eviter de tuer un node d'un autre projet sur la machine.
    $orphans = Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match "next" -and
        ($_.CommandLine -like "*HubFrontend*" -or $_.CommandLine -like "*hub-frontend*")
    }
    if ($orphans) {
        Write-Host "  [!] Process node orphelins detectes, nettoyage..." -ForegroundColor Yellow
        $orphans | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 2
    }
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
        # MODE PROD (next build + next start) au lieu de next dev:
        #  + 100% stable (pas de hot-reload = pas de chunks orphelins)
        #  + Plus rapide au runtime (build optimise une fois)
        #  - Plus lent au 1er launch apres modif (~20s build) mais OK
        #  - Pas de hot-reload (Marc utilise l app, ne develppe pas dessus)
        #
        # Detection: si .next/BUILD_ID existe et plus recent que les fichiers
        # source, pas besoin de re-build. Sinon, build avant de start.

        $nextCmd = "$frontendDir\node_modules\.bin\next.cmd"
        if (-not (Test-Path $nextCmd)) {
            Write-Host "  [X] node_modules manquant. Lance: cd $frontendDir; npm install --legacy-peer-deps" -ForegroundColor Red
            exit 1
        }

        $buildIdFile = "$frontendDir\.next\BUILD_ID"
        $needsBuild = $true
        if (Test-Path $buildIdFile) {
            # Verifier si build plus recent que les sources
            $buildTime = (Get-Item $buildIdFile).LastWriteTime
            $latestSrc = Get-ChildItem -Path "$frontendDir\app", "$frontendDir\components", "$frontendDir\lib" `
                -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.tsx','.ts','.js','.jsx','.css') } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latestSrc -and $latestSrc.LastWriteTime -le $buildTime) {
                $needsBuild = $false
                Write-Host "  [OK] Build prod a jour (skip rebuild)" -ForegroundColor Green
            }
        }

        if ($needsBuild) {
            Write-Host "  Build prod (Next.js, ~15-25s)..." -ForegroundColor Yellow
            Push-Location $frontendDir
            $env:NEXT_PUBLIC_HUB_API_URL = if ($env:NEXT_PUBLIC_HUB_API_URL) { $env:NEXT_PUBLIC_HUB_API_URL } else { "http://localhost:8000" }
            $buildOutput = & cmd /c "$nextCmd" build 2>&1
            $buildExit = $LASTEXITCODE
            Pop-Location
            if ($buildExit -ne 0) {
                Write-Host "  [X] Build prod echoue:" -ForegroundColor Red
                $buildOutput | Select-Object -Last 15 | ForEach-Object { Write-Host "      $_" -ForegroundColor DarkRed }
                exit 1
            }
            Write-Host "  [OK] Build prod ok" -ForegroundColor Green
        }

        Write-Host "  Demarrage prod server (next start)..." -ForegroundColor Yellow
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$nextCmd`"", "start" -WorkingDirectory $frontendDir -WindowStyle Hidden

        if (Wait-ForUrl "http://localhost:3000" 30 1) {
            Write-Host "  [OK] Frontend prod ready" -ForegroundColor Green
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
    # User-data-dir dedie : permet de tracker NOTRE process Chrome (pas celui de la session
    # principale) -> on peut waiter sa fin et trigger le cleanup automatique.
    $userDataDir = Join-Path $env:LOCALAPPDATA "HubPerso\chrome-profile"
    if (-not (Test-Path $userDataDir)) {
        New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
    }

    $chromeProc = Start-Process -FilePath $browser -ArgumentList @(
        "--app=http://localhost:3000",
        "--window-size=1400,900",
        "--user-data-dir=$userDataDir",
        "--disable-features=TranslateUI",
        "--no-default-browser-check",
        "--no-first-run"
    ) -PassThru
    Write-Host "  [OK] Hub perso ouvert" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Quand tu fermes la fenetre, le hub s'arrete tout seul." -ForegroundColor DarkGray

    # Attendre que l'user ferme Chrome, puis cleanup automatique
    if ($chromeProc) {
        try {
            $chromeProc.WaitForExit()
        } catch {
            # Process deja termine ou inaccessible
        }

        Write-Host ""
        Write-Host "[*] Chrome ferme - arret du hub..." -ForegroundColor Cyan

        # Kill watchdog en premier (sinon il va redemarrer hub-core qu'on essaie de tuer)
        if ($watchdogPid) {
            Stop-Process -Id $watchdogPid -Force -ErrorAction SilentlyContinue
        }

        # Kill hub-core uvicorn natif. Filtre strict : on cherche les python
        # appartenant au venv hub-core OU dont la CommandLine reference hub-core.
        # Evite de tuer un python d'un autre projet (ex: jupyter, autres apps).
        Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -match "uvicorn" -and $_.CommandLine -match "src\.main:app" -and
            ($_.ExecutablePath -like "*\hub-core\.venv\*" -or $_.CommandLine -like "*hub-core*")
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

        # Kill frontend Next.js. Filtre strict : il faut "next" ET un dossier
        # frontend hub. Evite de tuer un autre node sur la machine.
        Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -match "next" -and
            ($_.CommandLine -like "*HubFrontend*" -or $_.CommandLine -like "*hub-frontend*")
        } | ForEach-Object {
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

        # Stop Docker stack si elle tourne (mode Postgres)
        if (Test-CommandExists "docker") {
            $dockerInfo = docker info 2>&1
            if ($LASTEXITCODE -eq 0) {
                $running = docker ps --filter "name=hub-" --format "{{.Names}}" 2>&1
                if ($running) {
                    Push-Location "$PSScriptRoot\.."
                    docker compose -f docker-compose.dev.yml down 2>&1 | Out-Null
                    Pop-Location
                }
            }
        }

        Write-Host "[OK] Hub arrete proprement." -ForegroundColor Green
    }
} else {
    Write-Host "  [!] Chrome/Edge pas trouve. Ouvre manuellement http://localhost:3000" -ForegroundColor Yellow
    Start-Process "http://localhost:3000"
}

Write-Host ""
