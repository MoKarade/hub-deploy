# install-duckdns-task.ps1
# Programme update-duckdns.ps1 via Windows Task Scheduler (run toutes les 5 min).
#
# Usage : .\scripts\install-duckdns-task.ps1

$ErrorActionPreference = "Stop"

$taskName = "HubPerso-DuckDNS-Update"
$scriptPath = Join-Path $PSScriptRoot "update-duckdns.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "[X] update-duckdns.ps1 introuvable" -ForegroundColor Red
    exit 1
}

# Trigger : toutes les 5 minutes, indefiniment
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration ([System.TimeSpan]::MaxValue)

# Action : powershell.exe -File update-duckdns.ps1
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

# Principal : run as current user, NoInteractive
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

# Settings : run hidden, dont ask
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

# Remove existing task if any
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName $taskName `
    -Description "Hub perso - met a jour DuckDNS toutes les 5 min" `
    -Trigger $trigger `
    -Action $action `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "[OK] Tache programmee : $taskName (toutes les 5 min)" -ForegroundColor Green
Write-Host ""
Write-Host "  Run manuel : Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Status     : Get-ScheduledTaskInfo -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Desactiver : Unregister-ScheduledTask -TaskName $taskName -Confirm:`$false" -ForegroundColor DarkGray
Write-Host "  Logs       : Get-Content `$env:LOCALAPPDATA\duckdns-update.log -Tail 10" -ForegroundColor DarkGray
