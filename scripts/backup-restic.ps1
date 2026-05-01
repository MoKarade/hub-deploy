# backup-restic.ps1
# Backup chiffre incremental vers OneDrive via restic.
#
# Setup une fois :
#   1. Install restic : winget install restic.restic
#   2. Edite hub-deploy/.env :
#        RESTIC_PASSWORD=un-mot-de-passe-fort-pour-le-coffre
#        RESTIC_REPOSITORY=C:\Users\dessin14\OneDrive\hub-backup
#        BACKUP_PATHS=G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso;C:\HubFrontend
#   3. Init le repo (premier run) :
#        .\scripts\backup-restic.ps1 -Init
#   4. Backup manuel :
#        .\scripts\backup-restic.ps1
#   5. Programme via Task Scheduler (run quotidien 4h du matin) :
#        .\scripts\install-backup-task.ps1
#
# Restic = chiffrement AES-256, deduplication, snapshots incrementaux.
# Repo dans OneDrive = sync auto + offsite gratuit.

param(
    [switch]$Init,
    [switch]$Verify,
    [switch]$List,
    [string]$Restore
)

$ErrorActionPreference = "Stop"

# Charge .env
$envFile = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | Where-Object { $_ -match "^\s*([A-Z_]+)\s*=\s*(.+)\s*$" } | ForEach-Object {
        $matches = [regex]::Match($_, "^\s*([A-Z_]+)\s*=\s*(.+?)\s*$")
        if ($matches.Success) {
            $key = $matches.Groups[1].Value
            $val = $matches.Groups[2].Value.Trim('"').Trim("'")
            Set-Item -Path "Env:$key" -Value $val -ErrorAction SilentlyContinue
        }
    }
}

if (-not $env:RESTIC_PASSWORD -or -not $env:RESTIC_REPOSITORY) {
    Write-Host "[X] RESTIC_PASSWORD ou RESTIC_REPOSITORY manquant dans .env" -ForegroundColor Red
    Write-Host "    Cf. instructions en haut du script" -ForegroundColor Yellow
    exit 1
}

# Cherche restic dans PATH ou dans les emplacements connus
$resticBin = (Get-Command restic -ErrorAction SilentlyContinue).Source
if (-not $resticBin) {
    foreach ($p in @(
        "C:\ProgramData\restic\restic.exe",
        "C:\Program Files\restic\restic.exe",
        "$env:LOCALAPPDATA\Programs\restic\restic.exe"
    )) {
        if (Test-Path $p) { $resticBin = $p; break }
    }
}
if (-not $resticBin) {
    Write-Host "[X] restic pas installe. Lance: winget install restic.restic" -ForegroundColor Red
    Write-Host "    Ou telecharge le binaire depuis https://github.com/restic/restic/releases" -ForegroundColor Yellow
    exit 1
}
Set-Alias restic $resticBin -Scope Script

# === MODES ===

if ($Init) {
    Write-Host "[*] Init repository restic chiffre..." -ForegroundColor Cyan
    & restic init
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Repo initialise : $env:RESTIC_REPOSITORY" -ForegroundColor Green
    }
    exit $LASTEXITCODE
}

if ($Verify) {
    Write-Host "[*] Verification integrite repo..." -ForegroundColor Cyan
    & restic check --read-data-subset=10%
    exit $LASTEXITCODE
}

if ($List) {
    Write-Host "[*] Snapshots disponibles :" -ForegroundColor Cyan
    & restic snapshots
    exit $LASTEXITCODE
}

if ($Restore) {
    Write-Host "[*] Restauration snapshot $Restore..." -ForegroundColor Cyan
    $target = Join-Path $env:LOCALAPPDATA "hub-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    & restic restore $Restore --target $target
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Restaure dans : $target" -ForegroundColor Green
    }
    exit $LASTEXITCODE
}

# === MODE BACKUP (defaut) ===

$paths = if ($env:BACKUP_PATHS) {
    $env:BACKUP_PATHS -split ";" | Where-Object { $_ -and (Test-Path $_) }
} else {
    @(
        "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso",
        "C:\HubFrontend"
    ) | Where-Object { Test-Path $_ }
}

if (-not $paths) {
    Write-Host "[X] Aucun path valide a backup" -ForegroundColor Red
    exit 1
}

# Excludes (pas backup les dirs lourds + sensibles)
$excludeFile = Join-Path $env:LOCALAPPDATA "restic-excludes.txt"
@(
    "node_modules",
    ".next",
    ".venv",
    "venv",
    "__pycache__",
    "*.pyc",
    ".git/objects/pack",
    "raw_events/processed",
    "*.log",
    ".DS_Store",
    "Thumbs.db"
) | Set-Content -Path $excludeFile -Encoding utf8

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "[*] Backup $now ..." -ForegroundColor Cyan
Write-Host "    Paths : $($paths -join ', ')" -ForegroundColor DarkGray
Write-Host "    Repo  : $env:RESTIC_REPOSITORY" -ForegroundColor DarkGray
Write-Host ""

# Si la stack Postgres tourne, dump la DB d'abord (pg_dump dans hub-core volume)
if (Get-Command docker -ErrorAction SilentlyContinue) {
    $dbContainer = docker ps --filter "name=hub-dev-postgres" --format "{{.Names}}" 2>&1 | Select-Object -First 1
    if ($dbContainer) {
        $dumpDir = Join-Path $env:LOCALAPPDATA "hub-db-dumps"
        New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null
        $dumpFile = Join-Path $dumpDir "hubdb-$(Get-Date -Format 'yyyyMMdd-HHmmss').sql.gz"
        Write-Host "  Dump Postgres (hub-core)..." -ForegroundColor Yellow
        docker exec $dbContainer pg_dump -U hub hubdb 2>&1 | Out-File -Encoding utf8 $dumpFile.Replace(".gz", "")
        # Compress en gz si disponible (on skip si pas de gzip)
        if (Get-Command gzip -ErrorAction SilentlyContinue) {
            & gzip -f $dumpFile.Replace(".gz", "")
        }
        # Garde 7 derniers dumps
        Get-ChildItem $dumpDir -Filter "hubdb-*.sql*" | Sort-Object LastWriteTime -Descending |
            Select-Object -Skip 7 | Remove-Item -Force -ErrorAction SilentlyContinue
        $paths += $dumpDir
        Write-Host "  [OK] DB dumpee : $dumpFile" -ForegroundColor Green
    }
}

& restic backup --tag automated --exclude-file $excludeFile $paths
$exit = $LASTEXITCODE

if ($exit -eq 0) {
    Write-Host ""
    Write-Host "[*] Cleanup snapshots anciens (keep 7d 4w 12m)..." -ForegroundColor Cyan
    & restic forget `
        --keep-daily 7 `
        --keep-weekly 4 `
        --keep-monthly 12 `
        --prune
    Write-Host ""
    Write-Host "[OK] Backup termine." -ForegroundColor Green

    # Log
    $logFile = "$env:LOCALAPPDATA\restic-backup.log"
    Add-Content -Path $logFile -Value "$now OK paths=$($paths -join '|')"
} else {
    Write-Host "[X] Backup echoue (rc=$exit)" -ForegroundColor Red
}

exit $exit
