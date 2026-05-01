# update-duckdns.ps1
# Met a jour ton sous-domaine DuckDNS vers ton IP publique courante.
#
# Setup une fois :
#   1. Cree un compte gratuit sur https://www.duckdns.org/
#   2. Choisi un sous-domaine (ex: marc-hub) -> https://marc-hub.duckdns.org
#   3. Recupere ton TOKEN (en haut de la page)
#   4. Edite hub-deploy/.env :
#        DUCKDNS_DOMAIN=marc-hub      (sans le .duckdns.org)
#        DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   5. Test manuel : .\scripts\update-duckdns.ps1
#   6. Programme via Task Scheduler pour run toutes les 5 min :
#        .\scripts\install-duckdns-task.ps1
#
# Usage manuel : .\scripts\update-duckdns.ps1
# Renvoie : "OK" si IP mise a jour, "KO" sinon.

$ErrorActionPreference = "Stop"

# Charge .env (si present)
$envFile = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match "^\s*([A-Z_]+)\s*=\s*(.+)\s*$" } | ForEach-Object {
        $matches = [regex]::Match($_, "^\s*([A-Z_]+)\s*=\s*(.+?)\s*$")
        if ($matches.Success) {
            $key = $matches.Groups[1].Value
            $val = $matches.Groups[2].Value.Trim('"').Trim("'")
            Set-Item -Path "Env:$key" -Value $val -ErrorAction SilentlyContinue
        }
    }
}

$domain = $env:DUCKDNS_DOMAIN
$token = $env:DUCKDNS_TOKEN

if (-not $domain -or -not $token) {
    Write-Host "[X] DUCKDNS_DOMAIN ou DUCKDNS_TOKEN manquant dans .env" -ForegroundColor Red
    Write-Host "    Edite hub-deploy/.env (cf. instructions en haut du script)" -ForegroundColor Yellow
    exit 1
}

# Recupere IP publique courante (3 sources de fallback)
$publicIp = $null
foreach ($svc in @("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com")) {
    try {
        $resp = Invoke-WebRequest -Uri $svc -UseBasicParsing -TimeoutSec 5
        $body = if ($resp.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($resp.Content) } else { [string]$resp.Content }
        $publicIp = $body.Trim()
        if ($publicIp -match "^\d+\.\d+\.\d+\.\d+$") { break }
    } catch {
        $publicIp = $null
    }
}

if (-not $publicIp) {
    Write-Host "[X] Impossible de recuperer l'IP publique (3 services down)" -ForegroundColor Red
    exit 1
}

# Update DuckDNS
$url = "https://www.duckdns.org/update?domains=$domain&token=$token&ip=$publicIp"
try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
    # PowerShell 5.x retourne parfois Content en bytes - cast en string explicite
    $body = if ($r.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }
    $body = $body.Trim()
    if ($body -eq "OK") {
        $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[OK] $now -> $domain.duckdns.org = $publicIp" -ForegroundColor Green

        # Log persistant (au cas ou Task Scheduler tourne)
        $logFile = "$env:LOCALAPPDATA\duckdns-update.log"
        Add-Content -Path $logFile -Value "$now $domain.duckdns.org = $publicIp"
        # Rotate si log > 1 MB
        if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1MB) {
            Move-Item -Path $logFile -Destination "$logFile.old" -Force
        }
        exit 0
    } else {
        Write-Host "[X] DuckDNS a renvoye: $body" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[X] Erreur reseau DuckDNS : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
