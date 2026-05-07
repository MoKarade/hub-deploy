# install-ingest-scheduler-task.ps1
# Lance hub-ingest en mode scheduler daemon au logon.
# Le daemon contient APScheduler qui run insights_alerts daily 8h, proactive_alerts
# daily 7h, etc. selon ENABLED_CONNECTORS dans hub-ingest/.env.

$ErrorActionPreference = "Stop"

$taskName = "HubPerso-Ingest-Scheduler"
$venvPython = "C:\hub\hub-ingest\.venv\Scripts\python.exe"
$workDir = "C:\hub\hub-ingest"

if (-not (Test-Path $venvPython)) {
    Write-Host "[X] venv hub-ingest pas trouve : $venvPython" -ForegroundColor Red
    exit 1
}

# Wrapper PS qui set RUN_MODE=scheduler (default mais explicit) + log
$wrapperPath = "$workDir\.run-scheduler.ps1"
@"
Set-Location '$workDir'
`$env:RUN_MODE = 'scheduler'
`$logDir = 'C:\hub\hub-ingest\.logs'
New-Item -ItemType Directory -Force -Path `$logDir | Out-Null
`$logFile = Join-Path `$logDir ('scheduler-' + (Get-Date -Format 'yyyyMMdd') + '.log')
& '$venvPython' -m src.main *>> `$logFile
"@ | Out-File -FilePath $wrapperPath -Encoding UTF8 -Force

# Trigger : at logon
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$wrapperPath`"" `
    -WorkingDirectory $workDir

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Days 365) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName $taskName `
    -Description "Hub perso - Ingest scheduler daemon (insights_alerts, proactive_alerts via APScheduler)" `
    -Trigger $trigger `
    -Action $action `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "[OK] Tache programmee : $taskName (auto-start au logon)" -ForegroundColor Green
Write-Host ""
Write-Host "  Run manuel : Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Logs       : Get-Content C:\hub\hub-ingest\.logs\scheduler-*.log -Wait" -ForegroundColor DarkGray
