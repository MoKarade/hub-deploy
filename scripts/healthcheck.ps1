# healthcheck.ps1
# Verifie l'etat de chaque composant du hub.

Write-Host "[*] Personal Data Hub - healthcheck" -ForegroundColor Cyan
Write-Host ""

function Check-Endpoint($name, $url) {
    try {
        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($r.StatusCode -eq 200) {
            Write-Host "  [OK] $name : OK" -ForegroundColor Green
            return $true
        } else {
            Write-Host "  [!] $name : HTTP $($r.StatusCode)" -ForegroundColor Yellow
            return $false
        }
    } catch {
        Write-Host "  [X] $name : DOWN ($($_.Exception.Message))" -ForegroundColor Red
        return $false
    }
}

$results = @()
$results += Check-Endpoint "hub-core (API)" "http://localhost:8000/v1/health"
$results += Check-Endpoint "hub-core (Ready, DB+Ollama)" "http://localhost:8000/v1/ready"
$results += Check-Endpoint "Ollama"  "http://localhost:11434/api/tags"

# PostgreSQL via docker
$pgHealth = docker compose -f "$PSScriptRoot\..\docker-compose.dev.yml" ps --format json postgres 2>$null | ConvertFrom-Json
if ($pgHealth.Health -eq "healthy") {
    Write-Host "  [OK] PostgreSQL : healthy" -ForegroundColor Green
    $results += $true
} else {
    Write-Host "  [X] PostgreSQL : $($pgHealth.Health)" -ForegroundColor Red
    $results += $false
}

Write-Host ""
$ok = ($results | Where-Object { $_ -eq $true }).Count
$total = $results.Count
$color = if ($ok -eq $total) { "Green" } else { "Yellow" }
Write-Host "[*] Resume : $ok/$total composants OK" -ForegroundColor $color
