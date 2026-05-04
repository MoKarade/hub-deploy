# migrate-env-out-of-drive.ps1
# Deplace les fichiers .env hors de Google Drive (G:\Mon disque\...) pour eviter
# que les secrets soient uploades vers le cloud Google malgre .gitignore.
#
# Pourquoi : .gitignore ne protege que de Git. Google Drive sync TOUT ce qui est
# dans G:\Mon disque\ peu importe le .gitignore. Les secrets (.env) doivent
# vivre hors de Drive, et on cree un symlink pour que les scripts continuent
# a fonctionner.
#
# Cible : $env:USERPROFILE\.hub-secrets\<repo>.env
# Symlink : <repo>\.env -> $env:USERPROFILE\.hub-secrets\<repo>.env
#
# Necessite : droits admin OU Developer Mode active (Settings > For Developers).
# Fallback si pas de droits : on affiche un avertissement et on n'efface rien.
#
# Usage :
#   .\scripts\migrate-env-out-of-drive.ps1
#
# Idempotent : si le .env est deja un symlink, on skip.

$ErrorActionPreference = "Stop"

$root = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso"
$secretsHome = Join-Path $env:USERPROFILE ".hub-secrets"

function Test-IsSymlink([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $item = Get-Item $path -Force
    return ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
}

function Ensure-SecretsDir {
    if (-not (Test-Path $secretsHome)) {
        New-Item -ItemType Directory -Path $secretsHome -Force | Out-Null
        Write-Host "  [OK] Cree $secretsHome" -ForegroundColor Green
    } else {
        Write-Host "  [OK] $secretsHome existe deja" -ForegroundColor DarkGray
    }
}

function Migrate-EnvFile([string]$repoName) {
    $envPath = Join-Path $root "$repoName\.env"
    $targetPath = Join-Path $secretsHome "$repoName.env"

    Write-Host ""
    Write-Host "[*] Migration $repoName/.env" -ForegroundColor Cyan

    if (-not (Test-Path $envPath)) {
        Write-Host "  [-] $envPath n'existe pas, skip" -ForegroundColor DarkGray
        return
    }

    if (Test-IsSymlink $envPath) {
        Write-Host "  [OK] $envPath est deja un symlink, rien a faire" -ForegroundColor Green
        return
    }

    # Avant : .env est un vrai fichier dans Drive
    $sizeBefore = (Get-Item $envPath).Length
    Write-Host "  Avant : $envPath ($sizeBefore bytes, fichier reel dans Drive)" -ForegroundColor Yellow

    # 1. Si la cible existe deja, on le sauvegarde
    if (Test-Path $targetPath) {
        $backup = "$targetPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Move-Item -Path $targetPath -Destination $backup -Force
        Write-Host "  [!] Cible existait deja, sauvegarde dans $backup" -ForegroundColor Yellow
    }

    # 2. Move .env -> $secretsHome\<repo>.env
    Move-Item -Path $envPath -Destination $targetPath -Force
    Write-Host "  [OK] Deplace vers $targetPath" -ForegroundColor Green

    # 3. Cree le symlink (necessite admin OU Developer Mode)
    $created = $false
    try {
        New-Item -ItemType SymbolicLink -Path $envPath -Target $targetPath -ErrorAction Stop | Out-Null
        Write-Host "  [OK] Symlink cree : $envPath -> $targetPath" -ForegroundColor Green
        $created = $true
    } catch {
        Write-Host "  [!] Symlink echoue ($($_.Exception.Message))" -ForegroundColor Yellow
        # Fallback : tente une junction (mklink /J) pour les fichiers ce n'est pas
        # supporte, donc on essaie sur le dossier parent ou on copie + warn.
        Write-Host "  [!] Fallback : copie du fichier (Drive verra le secret)" -ForegroundColor Yellow
        try {
            Copy-Item -Path $targetPath -Destination $envPath -Force
            Write-Host "  [!!] AVERTISSEMENT : $envPath est une COPIE, pas un symlink" -ForegroundColor Red
            Write-Host "  [!!] Les modifs faites sur l'un ne seront PAS reflectees sur l'autre" -ForegroundColor Red
            Write-Host "  [!!] Pour corriger : active Developer Mode (Settings > For Developers)" -ForegroundColor Red
            Write-Host "  [!!] puis relance ce script. Ou lance ce script en admin." -ForegroundColor Red
        } catch {
            Write-Host "  [X] Copie aussi echouee : $($_.Exception.Message)" -ForegroundColor Red
            # On remet le fichier a sa place pour ne rien casser
            Move-Item -Path $targetPath -Destination $envPath -Force
            return
        }
    }

    if ($created) {
        Write-Host "  Apres : $envPath = SYMLINK -> $targetPath" -ForegroundColor Green
        Write-Host "  Drive ne synchronise QUE le symlink (pas le contenu reel du secret)" -ForegroundColor DarkGray
    }
}

# === Main ===

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host "    Migrate .env hors de Google Drive" -ForegroundColor Green
Write-Host "  ===========================================" -ForegroundColor Green

Write-Host ""
Write-Host "[*] Verification du dossier secrets..." -ForegroundColor Cyan
Ensure-SecretsDir

# Migre chaque repo qui a un .env
foreach ($repo in @("hub-deploy", "hub-core")) {
    Migrate-EnvFile $repo
}

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host "    Resume" -ForegroundColor Green
Write-Host "  ===========================================" -ForegroundColor Green
Write-Host ""
foreach ($repo in @("hub-deploy", "hub-core")) {
    $envPath = Join-Path $root "$repo\.env"
    $target = Join-Path $secretsHome "$repo.env"
    if (Test-Path $envPath) {
        if (Test-IsSymlink $envPath) {
            Write-Host "  [SYMLINK] $repo\.env -> $target" -ForegroundColor Green
        } else {
            Write-Host "  [WARN]    $repo\.env est encore un fichier reel dans Drive" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [-]       $repo\.env n'existe pas" -ForegroundColor DarkGray
    }
}
Write-Host ""
Write-Host "  Voir aussi : hub-deploy/docs/SECRETS-OUT-OF-DRIVE.md" -ForegroundColor DarkGray
Write-Host ""
