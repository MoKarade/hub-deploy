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
# CRUCIAL : wipe AUSSI les caches TypeScript + node_modules/.cache, sinon
# TS incremental cache reuse l'ancienne compilation d'api.ts -> bundle obsolete.
$tsCache = Join-Path $frontendDir "tsconfig.tsbuildinfo"
if (Test-Path $tsCache) { Remove-Item $tsCache -Force -ErrorAction SilentlyContinue }
$nmCache = Join-Path $frontendDir "node_modules\.cache"
if (Test-Path $nmCache) { Remove-Item $nmCache -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host "  [OK] Cache TS + node_modules/.cache wipe" -ForegroundColor Green

# Build prod + start (mode prod = stable)
# Sync next.config.mjs depuis Drive si on tourne depuis C:\HubFrontend
$driveConfig = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-frontend\next.config.mjs"
$localConfig = "$frontendDir\next.config.mjs"
if ((Test-Path $driveConfig) -and ($frontendDir -ne (Split-Path $driveConfig -Parent))) {
    Copy-Item $driveConfig $localConfig -Force -ErrorAction SilentlyContinue
}

$nextCmd = "$frontendDir\node_modules\.bin\next.cmd"
if (-not (Test-Path $nextCmd)) {
    Write-Host "  [X] node_modules manquant - lance npm install --legacy-peer-deps" -ForegroundColor Red
    exit 1
}

Write-Host "  Build prod (~15-25s)..." -ForegroundColor Yellow
Push-Location $frontendDir
# CRUCIAL : Next.js bake les NEXT_PUBLIC_* AU BUILD.
# Approche definitive : on ECRASE .env.production.local en UTF-8 SANS BOM
# (Set-Content -Encoding utf8 en PS5 ajoute un BOM que dotenv-loader ignore).
# Cette methode marche meme si l'env PowerShell n'est pas heritee correctement.
$apiUrl = if ($env:NEXT_PUBLIC_HUB_API_URL) { $env:NEXT_PUBLIC_HUB_API_URL } else { "http://localhost:8000" }
$mapsKey = ""
if (Test-Path "$frontendDir\.env.local") {
    $localContent = [System.IO.File]::ReadAllText("$frontendDir\.env.local")
    if ($localContent -match "NEXT_PUBLIC_GOOGLE_MAPS_API_KEY\s*=\s*(\S+)") {
        $mapsKey = $matches[1].Trim()
    }
}
$envContent = "NEXT_PUBLIC_HUB_API_URL=$apiUrl`n"
if ($mapsKey) { $envContent += "NEXT_PUBLIC_GOOGLE_MAPS_API_KEY=$mapsKey`n" }
# Ecrit SANS BOM (le PS5 default ajoute BOM avec Set-Content -Encoding utf8)
[System.IO.File]::WriteAllText(
    "$frontendDir\.env.production.local",
    $envContent,
    (New-Object System.Text.UTF8Encoding $false)
)
$env:NEXT_PUBLIC_HUB_API_URL = $apiUrl
Write-Host "  NEXT_PUBLIC_HUB_API_URL = $apiUrl (ecrit dans .env.production.local sans BOM)" -ForegroundColor DarkGray
& "$nextCmd" build 2>&1 | Out-Null
$buildExit = $LASTEXITCODE
# Note : on n'a plus besoin de verifier le bake d'env var car api.ts utilise
# maintenant getBaseUrl() runtime qui detecte window.location.hostname.
# Plus de risque de bundle "/api" foireux.
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
