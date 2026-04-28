# stop_hub.ps1
# Arrete la stack du Personal Data Hub.

$ErrorActionPreference = "Continue"

Write-Host "[*] Arret du Personal Data Hub..." -ForegroundColor Cyan
Push-Location $PSScriptRoot\..
docker compose -f docker-compose.dev.yml down
Pop-Location

Write-Host "[OK] Hub arrete. Les volumes persistent (postgres_data, redis_data)." -ForegroundColor Green
Write-Host "Pour tout supprimer (DB INCLUSE - dangereux) : docker compose -f docker-compose.dev.yml down -v" -ForegroundColor Yellow
