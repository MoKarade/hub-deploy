# install-frontend-task.ps1
# Programme un cron Windows Task Scheduler qui lance `npm run dev` au logon
# pour que le frontend Next.js soit toujours disponible sur :3000.

$ErrorActionPreference = "Stop"

$taskName = "HubPerso-Frontend-Dev"
$workDir = "C:\hub\hub-frontend"

# Detecte npm.cmd via PATH
$npmCmd = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
if (-not $npmCmd) {
    # Fallback : npm classique livre avec node
    $npmCmd = (Get-Command npm -ErrorAction SilentlyContinue).Source
}
if (-not $npmCmd) {
    Write-Host "[X] npm pas trouve dans PATH" -ForegroundColor Red
    exit 1
}
Write-Host "Using npm at : $npmCmd" -ForegroundColor DarkGray

# Wrapper PowerShell pour pouvoir cd + npm + log
$wrapperPath = "$workDir\.run-frontend.ps1"
@"
# Wrapper auto-genere - lance Next.js dev sur :3000
Set-Location '$workDir'
`$logDir = 'C:\hub\hub-frontend\.logs'
New-Item -ItemType Directory -Force -Path `$logDir | Out-Null
`$logFile = Join-Path `$logDir ('frontend-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
& '$npmCmd' run dev *>> `$logFile
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
    -Description "Hub perso - Frontend Next.js dev mode :3000 (auto-start au logon)" `
    -Trigger $trigger `
    -Action $action `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "[OK] Tache programmee : $taskName (auto-start au logon)" -ForegroundColor Green
Write-Host ""
Write-Host "  Run manuel : Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Status     : Get-ScheduledTaskInfo -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Stop       : Stop-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Logs       : Get-ChildItem $workDir\.logs -OrderBy LastWriteTime" -ForegroundColor DarkGray
