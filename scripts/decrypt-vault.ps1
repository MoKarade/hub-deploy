# decrypt-vault.ps1
# Dechiffre le vault de secrets perso (hub-secrets-vault.age) sur Drive.
# La cle privee age vit a C:\Users\<user>\.hub-secrets\age-key.txt et n est jamais sur Drive.

$ErrorActionPreference = "Stop"

# Find age.exe
function Find-AgeExe {
    $candidates = @(
        "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WinGet\Packages\FiloSottile.age_Microsoft.Winget.Source_8wekyb3d8bbwe\age\age.exe",
        "C:\Program Files\age\age.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $found = Get-Command age -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }

    $search = Get-ChildItem -Path "C:\Users\$env:USERNAME\AppData\Local\Microsoft\WinGet" -Filter "age.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($search) { return $search.FullName }

    return $null
}

$ageExe = Find-AgeExe
if (-not $ageExe) {
    Write-Host "[X] age.exe introuvable. Installation: winget install FiloSottile.age" -ForegroundColor Red
    exit 1
}

$keyFile = "C:\Users\$env:USERNAME\.hub-secrets\age-key.txt"
if (-not (Test-Path $keyFile)) {
    Write-Host "[X] Cle privee absente: $keyFile" -ForegroundColor Red
    Write-Host "    Restaure-la depuis ton backup (USB / password manager)." -ForegroundColor Yellow
    exit 1
}

# Find vault (in current Drive root or specified)
$vaultCandidates = @(
    "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-secrets-vault.age",
    ".\hub-secrets-vault.age"
)
$vault = $null
foreach ($v in $vaultCandidates) {
    if (Test-Path $v) { $vault = $v; break }
}
if (-not $vault) {
    Write-Host "[X] Vault introuvable. Specifie le chemin en argument." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Dechiffrement de $vault..."

# Decrypt to stdout (sans persister sur disque)
& $ageExe -d -i $keyFile $vault

Write-Host ""
Write-Host "[OK] Vault dechiffre. Copie ce que tu as besoin." -ForegroundColor Green
Write-Host "Pour rechiffrer apres modif:" -ForegroundColor DarkGray
Write-Host "  & '$ageExe' -e -r `$(cat C:\Users\$env:USERNAME\.hub-secrets\age-public-key.txt) -o '$vault' chemin\plain.yaml" -ForegroundColor DarkGray
