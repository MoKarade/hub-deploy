# clone_all.ps1
# Clone les 5 repos hub-* dans un dossier parent.
# Utile pour bootstrap un nouveau PC (cf. hub-docs/sessions/setup-autre-pc.md).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$TargetDir = "C:\hub",

    [Parameter(Mandatory = $false)]
    [string]$Owner = "MoKarade",

    [Parameter(Mandatory = $false)]
    [switch]$Pull
)

$ErrorActionPreference = "Stop"

$Repos = @(
    "hub-core",
    "hub-deploy",
    "hub-frontend",
    "hub-ingest",
    "hub-docs"
)

Write-Host "[*] Personal Data Hub - clone all" -ForegroundColor Cyan
Write-Host "    Target: $TargetDir"
Write-Host "    Owner : $Owner"
Write-Host ""

if (-not (Test-Path $TargetDir)) {
    Write-Host "[*] Création du dossier $TargetDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
}

Push-Location $TargetDir
try {
    foreach ($repo in $Repos) {
        $repoDir = Join-Path $TargetDir $repo
        $remoteUrl = "https://github.com/$Owner/$repo.git"

        if (Test-Path $repoDir) {
            if ($Pull) {
                Write-Host "[*] $repo existe — git pull" -ForegroundColor Yellow
                Push-Location $repoDir
                try {
                    git pull
                } finally {
                    Pop-Location
                }
            } else {
                Write-Host "[OK] $repo déjà cloné (skip — utilise -Pull pour mettre à jour)" -ForegroundColor Green
            }
        } else {
            Write-Host "[*] Clonage $remoteUrl → $repoDir" -ForegroundColor Cyan
            git clone $remoteUrl $repoDir
            if ($LASTEXITCODE -ne 0) {
                Write-Host "[X] Échec du clone $repo" -ForegroundColor Red
                exit 1
            }
            Write-Host "[OK] $repo cloné" -ForegroundColor Green
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "[OK] Tous les repos sont prêts dans $TargetDir" -ForegroundColor Green
Write-Host ""
Write-Host "Prochaines étapes (cf. hub-docs/sessions/setup-autre-pc.md) :" -ForegroundColor Cyan
Write-Host "  1. cd $TargetDir\hub-deploy"
Write-Host "  2. .\scripts\setup_windows.ps1   (vérifs + .env + ollama pull)"
Write-Host "  3. .\scripts\start_hub.ps1       (docker compose up + healthcheck)"
