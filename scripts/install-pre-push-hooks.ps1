# install-pre-push-hooks.ps1
# Installe un git pre-push hook dans les 5 repos qui appelle validate-all.ps1
# Empeche les push qui auraient cassé le CI.
#
# Usage: .\scripts\install-pre-push-hooks.ps1
# Pour bypass un push (urgent uniquement) : git push --no-verify

$ErrorActionPreference = "Stop"

$root = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso"
$validateScript = "$root\hub-deploy\scripts\validate-all.ps1"

$repoMap = @{
    "hub-core"     = "hub-core"
    "hub-frontend" = "hub-frontend"
    "hub-deploy"   = "hub-deploy"
    "hub-ingest"   = "hub-ingest"
    "hub-docs"     = "hub-docs"
}

Write-Host ""
Write-Host "  Installation des git pre-push hooks dans les 5 repos..." -ForegroundColor Cyan
Write-Host ""

foreach ($repoDir in $repoMap.Keys) {
    $repoPath = "$root\$repoDir"
    $hookPath = "$repoPath\.git\hooks\pre-push"
    $repoArg = $repoMap[$repoDir]

    if (-not (Test-Path "$repoPath\.git")) {
        Write-Host "  [skip] $repoDir (pas un repo Git)" -ForegroundColor DarkGray
        continue
    }

    # Hook bash (compatible Git for Windows + Git Bash)
    $hookContent = @"
#!/bin/sh
# Auto-genere par install-pre-push-hooks.ps1.
# Lance validate-all.ps1 -Repo $repoArg avant chaque push.
# Bypass: git push --no-verify

echo ""
echo "[pre-push] Validation locale de $repoArg avant push..."

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$validateScript" -Repo $repoArg
if [ \$? -ne 0 ]; then
    echo ""
    echo "[pre-push] X Validation echouee. Fix les erreurs avant de pusher."
    echo "[pre-push] Pour bypass (urgence uniquement): git push --no-verify"
    exit 1
fi
echo "[pre-push] OK Push autorise."
exit 0
"@

    # Écrire le hook (LF line endings pour bash sh)
    [System.IO.File]::WriteAllText($hookPath, $hookContent.Replace("`r`n", "`n"))

    # Le rendre exécutable (Git pour Windows respecte le bit + le ch perm)
    Write-Host "  [OK] $repoDir : hook installe" -ForegroundColor Green
}

Write-Host ""
Write-Host "  [OK] Pre-push hooks installes dans $($repoMap.Count) repos" -ForegroundColor Green
Write-Host ""
Write-Host "  A partir de maintenant : git push lance validate-all automatiquement." -ForegroundColor White
Write-Host "  Si la validation echoue, push bloque." -ForegroundColor White
Write-Host ""
Write-Host "  Pour bypass un push urgent : git push --no-verify" -ForegroundColor DarkGray
