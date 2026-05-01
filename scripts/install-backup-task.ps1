# install-backup-task.ps1
# Programme backup-restic.ps1 via Task Scheduler (run quotidien 4h du matin).

$ErrorActionPreference = "Stop"

$taskName = "HubPerso-Backup-Restic"
$scriptPath = Join-Path $PSScriptRoot "backup-restic.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "[X] backup-restic.ps1 introuvable" -ForegroundColor Red
    exit 1
}

# Trigger : tous les jours a 4h du matin
$trigger = New-ScheduledTaskTrigger -Daily -At 4:00am

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""

$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Limited

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -WakeToRun

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName $taskName `
    -Description "Hub perso - Backup chiffre quotidien vers OneDrive (restic)" `
    -Trigger $trigger `
    -Action $action `
    -Principal $principal `
    -Settings $settings | Out-Null

Write-Host "[OK] Tache programmee : $taskName (tous les jours 04h00)" -ForegroundColor Green
Write-Host ""
Write-Host "  Run manuel : Start-ScheduledTask -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Status     : Get-ScheduledTaskInfo -TaskName $taskName" -ForegroundColor DarkGray
Write-Host "  Snapshots  : .\scripts\backup-restic.ps1 -List" -ForegroundColor DarkGray
Write-Host "  Verify     : .\scripts\backup-restic.ps1 -Verify" -ForegroundColor DarkGray
