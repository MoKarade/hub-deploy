# start-tunnel.ps1
# Cree un tunnel Cloudflare pour exposer le hub sur Internet (acces depuis telephone).
#
# 2 modes:
#   QUICK (default): URL temporaire xxx.trycloudflare.com (change a chaque restart)
#                    Utile pour tester. PAS de protection auth (acces public!).
#
#   NAMED:           URL stable hub.tondomaine.com via compte Cloudflare.
#                    Permet d'ajouter Cloudflare Access (login Google obligatoire).
#                    Voir docs/CLOUDFLARE-TUNNEL.md pour setup une fois.
#
# Usage:
#   .\scripts\start-tunnel.ps1                 # Quick tunnel (frontend uniquement)
#   .\scripts\start-tunnel.ps1 -Mode named     # Named tunnel (config dans cloudflared/config.yml)
#   .\scripts\start-tunnel.ps1 -Mode quick -Target backend  # Quick tunnel pour hub-core API

param(
    [ValidateSet("quick", "named")]
    [string]$Mode = "quick",

    [ValidateSet("frontend", "backend")]
    [string]$Target = "frontend"
)

$ErrorActionPreference = "Stop"

$cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
if (-not (Test-Path $cloudflared)) {
    $cmd = Get-Command cloudflared -ErrorAction SilentlyContinue
    if (-not $cmd) {
        Write-Host "[X] cloudflared introuvable. Installe via: winget install Cloudflare.cloudflared" -ForegroundColor Red
        exit 1
    }
    $cloudflared = $cmd.Source
}

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "    Cloudflare Tunnel - Personal Data Hub" -ForegroundColor Cyan
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host ""

if ($Mode -eq "quick") {
    $port = if ($Target -eq "backend") { 8000 } else { 3000 }
    $localUrl = "http://localhost:$port"

    # Verifier que le service tourne
    try {
        $r = Invoke-WebRequest -Uri $localUrl -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        Write-Host "  [OK] Service local actif: $localUrl ($($r.StatusCode))" -ForegroundColor Green
    } catch {
        Write-Host "  [!] $localUrl ne repond pas. Lance d'abord launch-app.ps1." -ForegroundColor Yellow
        Write-Host "      On lance le tunnel quand meme - utile si tu demarres le service apres." -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "  Mode: QUICK TUNNEL (URL temporaire, change a chaque restart)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  ATTENTION SECURITE:" -ForegroundColor Red
    Write-Host "  ----------------------" -ForegroundColor Red
    Write-Host "  - L'URL est PUBLIQUE: n'importe qui qui la connait y a acces" -ForegroundColor Red
    Write-Host "  - Pas d'authentification (Cloudflare Access necessite Mode named)" -ForegroundColor Red
    Write-Host "  - NE PARTAGE JAMAIS l'URL sur Internet" -ForegroundColor Red
    Write-Host "  - Ferme le tunnel (Ctrl+C) quand tu n'en as plus besoin" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Pour usage long-terme (URL stable + auth):" -ForegroundColor White
    Write-Host "    .\scripts\start-tunnel.ps1 -Mode named" -ForegroundColor White
    Write-Host "    Voir docs/CLOUDFLARE-TUNNEL.md pour setup une fois" -ForegroundColor White
    Write-Host ""

    Write-Host "  Demarrage du tunnel vers $localUrl ..." -ForegroundColor Cyan
    Write-Host ""

    & $cloudflared tunnel --url $localUrl
}
elseif ($Mode -eq "named") {
    $configPath = Join-Path $PSScriptRoot "..\cloudflared\config.yml"
    if (-not (Test-Path $configPath)) {
        Write-Host "  [X] Config absente: $configPath" -ForegroundColor Red
        Write-Host "      Voir docs/CLOUDFLARE-TUNNEL.md pour le setup une fois." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "  Mode: NAMED TUNNEL (URL stable + Cloudflare Access compatible)" -ForegroundColor Green
    Write-Host "  Config: $configPath" -ForegroundColor DarkGray
    Write-Host ""
    & $cloudflared tunnel --config $configPath run
}
