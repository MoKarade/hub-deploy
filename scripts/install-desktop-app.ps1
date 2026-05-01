# install-desktop-app.ps1
# Installe le Hub perso comme une vraie app desktop sur Windows.
# Cree un raccourci bureau + entree menu Demarrer.

$ErrorActionPreference = "Stop"

Write-Host "[*] Installation Hub perso comme app desktop..." -ForegroundColor Cyan

$scriptDir = $PSScriptRoot
$launchScript = Join-Path $scriptDir "launch-app.ps1"
$desktop = [System.Environment]::GetFolderPath('Desktop')
$startMenu = [System.Environment]::GetFolderPath('StartMenu')
$hubProgramsDir = Join-Path $startMenu "Programs\Hub perso"

if (-not (Test-Path $launchScript)) {
    Write-Host "  [X] launch-app.ps1 introuvable a $launchScript" -ForegroundColor Red
    exit 1
}

# Generation icone (vert avec H)
$iconPath = Join-Path $scriptDir "..\hub-perso.ico"
if (-not (Test-Path $iconPath)) {
    Write-Host "  Generation icone..." -ForegroundColor Yellow
    Add-Type -AssemblyName System.Drawing
    $bitmap = New-Object System.Drawing.Bitmap 256, 256
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(256, 256)),
        ([System.Drawing.Color]::FromArgb(92, 219, 149)),
        ([System.Drawing.Color]::FromArgb(58, 163, 112))
    )
    $g.FillRectangle($brush, 0, 0, 256, 256)
    $font = New-Object System.Drawing.Font("Arial", 140, [System.Drawing.FontStyle]::Bold)
    $stringFormat = New-Object System.Drawing.StringFormat
    $stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
    $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
    $textBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(10, 14, 20))
    $g.DrawString("H", $font, $textBrush, (New-Object System.Drawing.RectangleF(0, 0, 256, 256)), $stringFormat)
    $bitmap.Save($iconPath, [System.Drawing.Imaging.ImageFormat]::Icon)
    $g.Dispose()
    $bitmap.Dispose()
    Write-Host "  [OK] Icone genere a $iconPath" -ForegroundColor Green
}

# Raccourci bureau
$shortcutPath = Join-Path $desktop "Hub perso.lnk"
Write-Host "  Creation raccourci bureau..." -ForegroundColor Yellow

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launchScript`""
$shortcut.WorkingDirectory = Split-Path $launchScript
$shortcut.WindowStyle = 7
$shortcut.Description = "Personal Data Hub - IA locale + data centralisees"
if (Test-Path $iconPath) {
    $shortcut.IconLocation = $iconPath
}
$shortcut.Save()
Write-Host "  [OK] Raccourci bureau cree" -ForegroundColor Green

# Menu Demarrer
if (-not (Test-Path $hubProgramsDir)) {
    New-Item -ItemType Directory -Path $hubProgramsDir -Force | Out-Null
}
$startShortcut = Join-Path $hubProgramsDir "Hub perso.lnk"
$shortcut2 = $shell.CreateShortcut($startShortcut)
$shortcut2.TargetPath = "powershell.exe"
$shortcut2.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launchScript`""
$shortcut2.WorkingDirectory = Split-Path $launchScript
$shortcut2.WindowStyle = 7
$shortcut2.Description = "Personal Data Hub"
if (Test-Path $iconPath) {
    $shortcut2.IconLocation = $iconPath
}
$shortcut2.Save()
Write-Host "  [OK] Entree menu Demarrer creee" -ForegroundColor Green

# Cleanup d'anciennes icones Stop si elles existent (legacy)
Remove-Item -Path (Join-Path $desktop "Hub perso - Stop.lnk") -Force -ErrorAction SilentlyContinue
Remove-Item -Path (Join-Path $hubProgramsDir "Hub perso - Stop.lnk") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[*] Installation terminee !" -ForegroundColor Green
Write-Host ""
Write-Host "  Une seule icone sur le bureau : 'Hub perso' (vert, H)" -ForegroundColor White
Write-Host "  Click pour lancer. Ferme la fenetre pour tout arreter." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Le 1er lancement prend ~1-2 min (setup venv + build frontend)" -ForegroundColor DarkGray
Write-Host "  Les suivants : ~5-10 sec." -ForegroundColor DarkGray
Write-Host ""
