# install-chrome-history-task.ps1
# Programme un cron Windows Task Scheduler qui lance hub-ingest mode chrome-history
# toutes les 6h. Lit le SQLite Chrome (lock-safe via shutil.copy2), extrait les
# visites delta depuis le dernier sync (cursor dans state.json), POST au hub-core.
#
# Pre-requis : venv hub-ingest setup (C:\hub\hub-ingest\.venv) + .env configure.

$ErrorActionPreference = "Stop"

$taskName = "HubPerso-ChromeHistory-Sync"
$venvPython = "C:\hub\hub-ingest\.venv\Scripts\python.exe"
$workDir = "C:\hub\hub-ingest"

if (-not (Test-Path $venvPython)) {
    Write-Host "[X] venv hub-ingest pas trouve : $venvPython" -ForegroundColor Red
    Write-Host "    Setup : python -m venv .venv puis pip install -e ." -ForegroundColor Yellow
    exit 1
}

# Trigger : toutes les 6h, partant maintenant
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
    -RepetitionInterval (New-TimeSpan -Hours 6)

# Action : python -m src.main avec RUN_MODE=chrome-history
$action = New-ScheduledTaskAction `
    -Execute $venvPython `
    -Argument "-m src.main" `
    -WorkingDirectory $workDir

$envVar = "RUN_MODE=chrome-history"

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# On utilise un wrapper PowerShell pour set RUN_MODE avant de lancer python
$wrapperScript = @"
`$env:RUN_MODE = 'chrome-history'
& '$venvPython' -m src.main
"@
$wrapperPath = "$workDir\.run-chrome-history.ps1"
$wrapperScript | Out-File -FilePath $wrapperPath -Encoding UTF8 -Force

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$wrapperPath`"" `
    -WorkingDirectory $workDir

Register-ScheduledTask `
    -TaskName $taskName `
    -Description "Hub perso - Sync Chrome history toutes les 6h vers /v1/browser/sync" `
    -Trigger $trigger `
    -Action $action `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "[OK] Tache programmee : $taskName (toutes les 6h)" -ForegroundColor Green
Write-Host ""
Write-Host "  Run manuel : Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Status     : Get-ScheduledTaskInfo -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Logs       : tail C:\hub\raw_events\chrome\*.json" -ForegroundColor DarkGray
