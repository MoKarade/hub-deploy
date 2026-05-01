# restart-frontend.ps1
# Force restart propre du frontend Next.js (clean .next cache + relance).
# A utiliser SI l'app affiche une erreur 500 type "Cannot find module './XXX.js'".
#
# Usage: .\scripts\restart-frontend.ps1
# Ou raccourci bureau: cf. install-desktop-app.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  Restart frontend - clean cache .next" -ForegroundColor Cyan
Write-Host ""

# Kill node procs lies au frontend
$killed = 0
Get-Process node -ErrorAction SilentlyContinue | ForEach-Object {
    $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)" -ErrorAction SilentlyContinue).CommandLine
    if ($cmdLine -match "next" -or $cmdLine -match "HubFrontend") {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killed++
    }
}
if ($killed -gt 0) {
    Write-Host "  [OK] $killed process node tues" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# Wipe .next
$frontendDir = if (Test-Path "C:\HubFrontend\package.json") {
    "C:\HubFrontend"
} else {
    "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-frontend"
}
$nextCache = Join-Path $frontendDir ".next"
if (Test-Path $nextCache) {
    Remove-Item -Path $nextCache -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Cache .next/ wipe" -ForegroundColor Green
}

# Build prod + start (mode prod = stable)
$nextCmd = "$frontendDir\node_modules\.bin\next.cmd"
if (-not (Test-Path $nextCmd)) {
    Write-Host "  [X] node_modules manquant - lance npm install --legacy-peer-deps" -ForegroundColor Red
    exit 1
}

Write-Host "  Build prod (~15-25s)..." -ForegroundColor Yellow
Push-Location $frontendDir
# CRUCIAL : Next.js bake les env NEXT_PUBLIC_* AU MOMENT DU BUILD.
# Sans ca, BASE_URL = '/api' (fallback) -> 404 sur tous les calls API depuis le bundle.
# Methode robuste : ecrire .env.production.local que Next.js lit automatiquement.
$apiUrl = if ($env:NEXT_PUBLIC_HUB_API_URL) { $env:NEXT_PUBLIC_HUB_API_URL } else { "http://localhost:8000" }
$mapsKey = if ($env:NEXT_PUBLIC_GOOGLE_MAPS_API_KEY) { $env:NEXT_PUBLIC_GOOGLE_MAPS_API_KEY } else { "" }
# Preserve les autres NEXT_PUBLIC_* qu'on aurait pu set (ex: maps key) en lisant .env.local existant
$envProd = @()
if (Test-Path "$frontendDir\.env.local") {
    Get-Content "$frontendDir\.env.local" | Where-Object { $_ -match "^\s*NEXT_PUBLIC_" -and $_ -notmatch "NEXT_PUBLIC_HUB_API_URL" } | ForEach-Object { $envProd += $_ }
}
$envProd += "NEXT_PUBLIC_HUB_API_URL=$apiUrl"
$envProd | Set-Content "$frontendDir\.env.production.local" -Encoding utf8
Write-Host "  .env.production.local : NEXT_PUBLIC_HUB_API_URL=$apiUrl" -ForegroundColor DarkGray
$env:NEXT_PUBLIC_HUB_API_URL = $apiUrl
& "$nextCmd" build 2>&1 | Out-Null
$buildExit = $LASTEXITCODE
Pop-Location
if ($buildExit -ne 0) {
    Write-Host "  [X] Build echoue, check 'cd $frontendDir; npm run build'" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Build ok, demarrage serveur..." -ForegroundColor Green
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$nextCmd`"", "start" -WorkingDirectory $frontendDir -WindowStyle Hidden
Write-Host ""

# Wait for ready
Write-Host "  Attente du serveur..." -ForegroundColor DarkGray
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 2
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:3000" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            Write-Host "  [OK] Frontend ready apres $($i*2)s" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Recharge ton browser (Ctrl+Shift+R)" -ForegroundColor White
            exit 0
        }
    } catch { }
}
Write-Host "  [!] Timeout 60s - check les logs (Get-Process node)" -ForegroundColor Yellow
exit 1
