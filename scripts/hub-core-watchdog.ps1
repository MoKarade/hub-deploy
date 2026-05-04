# hub-core-watchdog.ps1
# Process supervisor : auto-restart hub-core uvicorn s'il crashe.
# Lance en background par launch-app.ps1 (ne pas appeler directement).
#
# Boucle infinie qui :
#  1. Verifie si hub-core repond a /v1/health
#  2. Si non : kill les uvicorn lies, relance, attend healthy
#  3. Sleep 30s, repeat
#
# S'arrete quand le launch principal (Chrome) ferme.

param(
    [string]$HubCoreDir = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-core",
    [int]$CheckIntervalSec = 30
)

$ErrorActionPreference = "Continue"

$logFile = "$env:LOCALAPPDATA\hub-core-watchdog.log"
$py = "$HubCoreDir\.venv\Scripts\python.exe"

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # Rotation : si log > 10MB, rename en .old (et ecrase l'ancien .old).
    if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 10MB) {
        $oldLog = "$logFile.old"
        if (Test-Path $oldLog) { Remove-Item $oldLog -Force -ErrorAction SilentlyContinue }
        Move-Item -Path $logFile -Destination $oldLog -Force -ErrorAction SilentlyContinue
    }
    Add-Content -Path $logFile -Value "$ts $msg"
}

function Test-HubCoreHealth {
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/v1/health" `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        return $r.StatusCode -eq 200
    } catch {
        return $false
    }
}

function Start-HubCore {
    if (-not (Test-Path $py)) {
        Log "[X] python introuvable a $py"
        return
    }
    # Kill toute instance existante - on filtre strictement les python
    # qui appartiennent au venv hub-core (ExecutablePath) ou dont la CommandLine
    # contient hub-core. Eviter de tuer un python d'un autre projet.
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match "uvicorn" -and $_.CommandLine -match "src\.main:app" -and
        ($_.ExecutablePath -like "*\hub-core\.venv\*" -or $_.CommandLine -like "*hub-core*")
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    # Auto-migrate avant lancement
    Push-Location $HubCoreDir
    & $py init_sqlite.py 2>&1 | Out-Null
    Pop-Location
    # Relance
    Start-Process -FilePath $py `
        -ArgumentList @("-m", "uvicorn", "src.main:app", "--port", "8000", "--host", "127.0.0.1") `
        -WorkingDirectory $HubCoreDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput "$env:LOCALAPPDATA\hub-core.log" `
        -RedirectStandardError "$env:LOCALAPPDATA\hub-core.log.err"
    Log "[OK] hub-core restart trigger"
}

Log "[*] Watchdog start (check toutes les ${CheckIntervalSec}s)"

# Circuit breaker : apres N restarts consecutifs qui echouent, on dort 5 min
# au lieu de hammerer en boucle. Evite la boucle infinie de restart si un bug
# permanent empeche hub-core de demarrer.
$consecutiveFailures = 0
$maxConsecutiveFailures = 5

# Boucle principale
while ($true) {
    if (-not (Test-HubCoreHealth)) {
        Log "[!] hub-core DOWN, restarting... (failures=$consecutiveFailures/$maxConsecutiveFailures)"
        Start-HubCore
        # Attente up to 60s pour devenir healthy
        $attempt = 0
        while ($attempt -lt 30 -and -not (Test-HubCoreHealth)) {
            Start-Sleep -Seconds 2
            $attempt++
        }
        if (Test-HubCoreHealth) {
            Log "[OK] hub-core back up apres $($attempt*2)s"
            $consecutiveFailures = 0  # reset le compteur sur succes
        } else {
            $consecutiveFailures++
            Log "[X] hub-core ne revient pas (60s timeout, failures=$consecutiveFailures)"
            if ($consecutiveFailures -ge $maxConsecutiveFailures) {
                Log "[!!] Circuit breaker open, sleeping 5 min avant nouvelle tentative"
                Start-Sleep -Seconds 300
                $consecutiveFailures = 0  # reset apres la pause longue
            }
        }
    } else {
        # Tout va bien : reset le compteur
        $consecutiveFailures = 0
    }
    Start-Sleep -Seconds $CheckIntervalSec
}
