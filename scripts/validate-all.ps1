# validate-all.ps1
# Lance TOUS les checks CI localement, sur les 5 repos.
# A utiliser AVANT chaque push pour eviter les fails CI distants.
#
# Usage: .\scripts\validate-all.ps1 [-Repo hub-core|hub-frontend|hub-deploy|hub-ingest|hub-docs|all]

param(
    [ValidateSet("all", "hub-core", "hub-frontend", "hub-deploy", "hub-ingest", "hub-docs")]
    [string]$Repo = "all"
)

$ErrorActionPreference = "Continue"
$root = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso"
$totalFails = 0

function Print-Header($name) {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  $name" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
}

function Run-Check($name, $cmd) {
    Write-Host "  [...] $name" -ForegroundColor DarkGray -NoNewline
    $output = & $cmd 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`r  [OK]  $name      " -ForegroundColor Green
        return 0
    } else {
        Write-Host "`r  [FAIL] $name     " -ForegroundColor Red
        $output | Select-Object -Last 5 | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkRed }
        return 1
    }
}

# ── hub-core ──────────────────────────────────────────────────────────────────

if ($Repo -in @("all", "hub-core")) {
    Print-Header "hub-core (Python: ruff + pytest)"
    Push-Location "$root\hub-core"
    $totalFails += Run-Check "Ruff lint"           { python -m ruff check src tests }
    $totalFails += Run-Check "Ruff format check"   { python -m ruff format --check src tests }
    $totalFails += Run-Check "Pytest"              { python -m pytest --tb=short -q }
    Pop-Location
}

# ── hub-ingest ────────────────────────────────────────────────────────────────

if ($Repo -in @("all", "hub-ingest")) {
    Print-Header "hub-ingest (Python: ruff + pytest)"
    Push-Location "$root\hub-ingest"
    $totalFails += Run-Check "Ruff lint"           { python -m ruff check src tests }
    $totalFails += Run-Check "Ruff format check"   { python -m ruff format --check src tests }
    $totalFails += Run-Check "Pytest"              { python -m pytest --tb=short -q }
    Pop-Location
}

# ── hub-frontend ──────────────────────────────────────────────────────────────

if ($Repo -in @("all", "hub-frontend")) {
    Print-Header "hub-frontend (Next.js: lint + typecheck + build)"
    # Use C:\HubFrontend si dispo (workaround chemin Drive avec espaces)
    $feDir = if (Test-Path "C:\HubFrontend\package.json") { "C:\HubFrontend" } else { "$root\hub-frontend" }
    Push-Location $feDir
    $totalFails += Run-Check "Lint"        { cmd /c "node_modules\.bin\next.cmd lint" 2>&1 }
    $totalFails += Run-Check "Typecheck"   { cmd /c "node_modules\.bin\tsc.cmd --noEmit" 2>&1 }
    $env:NEXT_PUBLIC_HUB_API_URL = "/api"
    $totalFails += Run-Check "Build prod"  { cmd /c "node_modules\.bin\next.cmd build" 2>&1 }
    Pop-Location
}

# ── hub-deploy ────────────────────────────────────────────────────────────────

if ($Repo -in @("all", "hub-deploy")) {
    Print-Header "hub-deploy (yaml + docker compose)"
    Push-Location "$root\hub-deploy"

    # Validate yaml files (sauf .github)
    $yamlOk = $true
    Get-ChildItem -Recurse -Include "*.yml","*.yaml" | Where-Object { $_.FullName -notmatch '\.github' } | ForEach-Object {
        & python -c "import yaml; yaml.safe_load(open(r'$($_.FullName)'))" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { $yamlOk = $false; Write-Host "    [FAIL yaml] $($_.Name)" -ForegroundColor Red }
    }
    if ($yamlOk) { Write-Host "  [OK]  YAML syntax (cloudflared, docker-compose, sops)" -ForegroundColor Green }
    else { $totalFails++ }

    # Test que .env.example couvre tous les :?required
    $totalFails += Run-Check ".env.example couvre :?required" {
        python -c @"
import re, os
os.chdir(r'$root\hub-deploy')
env = {}
with open('.env.example') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k] = v.strip()
missing_total = []
for compose in ['docker-compose.dev.yml', 'docker-compose.prod.yml']:
    with open(compose) as f:
        content = f.read()
    required = re.findall(r'\$\{([A-Z_]+):\?required\}', content)
    missing = [v for v in required if not env.get(v)]
    if missing:
        missing_total.extend(missing)
if missing_total:
    print('Missing in .env.example: ' + ', '.join(set(missing_total)))
    exit(1)
exit(0)
"@
    }
    Pop-Location
}

# ── hub-docs ──────────────────────────────────────────────────────────────────

if ($Repo -in @("all", "hub-docs")) {
    Print-Header "hub-docs (markdown lint - non-blocking en CI)"
    Write-Host "  [skip] markdown lint = continue-on-error en CI (non-blocking)" -ForegroundColor DarkGray
    Write-Host "         CI verifie quand meme la presence des fichiers." -ForegroundColor DarkGray
}

# ── Resume ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
if ($totalFails -eq 0) {
    Write-Host "  [OK] Tous les checks CI passent localement" -ForegroundColor Green
    Write-Host "       Push sans crainte." -ForegroundColor Green
    exit 0
} else {
    Write-Host "  [FAIL] $totalFails checks ont echoue" -ForegroundColor Red
    Write-Host "         Fix avant de pusher (sinon le CI fail)." -ForegroundColor Red
    exit 1
}
