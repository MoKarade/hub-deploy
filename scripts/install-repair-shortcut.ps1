# install-repair-shortcut.ps1
# Cree un raccourci bureau "Reparer Hub" qui lance restart-frontend.ps1.
# A double-cliquer si l'app foire (erreur 500, page bloquee, etc.)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$repairScript = Join-Path $scriptDir "restart-frontend.ps1"
$desktop = [System.Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop "Reparer Hub.lnk"

if (-not (Test-Path $repairScript)) {
    Write-Host "[X] restart-frontend.ps1 introuvable" -ForegroundColor Red
    exit 1
}

# Reuse hub-perso.ico if exists, sinon une icone systeme
$iconPath = Join-Path $scriptDir "..\hub-perso.ico"
if (-not (Test-Path $iconPath)) {
    $iconPath = "$env:SystemRoot\System32\shell32.dll,238"  # icone reparation
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$repairScript`""
$shortcut.WorkingDirectory = Split-Path $repairScript
$shortcut.WindowStyle = 1  # normal (visible) pour voir le progress
$shortcut.Description = "Reparer le Hub perso (clean cache + restart frontend)"
$shortcut.IconLocation = $iconPath
$shortcut.Save()

Write-Host "[OK] Raccourci bureau cree: $shortcutPath" -ForegroundColor Green
Write-Host ""
Write-Host "Si l'app affiche une erreur 500 ou bloquee:" -ForegroundColor White
Write-Host "  1. Double-clique 'Reparer Hub' sur le bureau" -ForegroundColor White
Write-Host "  2. Attends ~10s (recompile)" -ForegroundColor White
Write-Host "  3. Recharge ton browser (Ctrl+Shift+R)" -ForegroundColor White
