# Vault de secrets — age + sops

Tous les secrets sensibles (tokens API, credentials banque, clés, etc.) sont chiffrés avec [age](https://github.com/FiloSottile/age) via [sops](https://github.com/getsops/sops). Ils ne quittent JAMAIS le repo en clair.

Voir [ADR-0006](../../hub-docs/decisions/0006-age-sops-vs-vault.md) pour la justification du choix.

## Setup initial (une fois)

Le script `scripts/init_secrets.ps1` automatise tout :

```powershell
cd C:\hub\hub-deploy
.\scripts\init_secrets.ps1
```

Le script :
1. Vérifie que `age` et `sops` sont installés
2. Génère ta clé age (`~/.age/hub.key`) si elle n'existe pas
3. Affiche la public key
4. Met à jour `.sops.yaml` avec ta pubkey

Manuellement (si tu préfères) :

```powershell
# 1. Génère ta clé age personnelle
age-keygen -o $env:USERPROFILE\.age\hub.key

# 2. Récupère la public key
age-keygen -y $env:USERPROFILE\.age\hub.key
# → age1...   (colle dans .sops.yaml)
```

## ⚠️ Sauvegarde de la clé privée — critique

**Si tu perds `~/.age/hub.key`, TOUS les backups restic deviennent illisibles.**

Convention obligatoire :
1. Copie la clé sur **2 clés USB physiques** :
   - Clé chez toi (tiroir bureau)
   - Clé chez tes parents (geo-redondance contre incendie/inondation)
2. **JAMAIS** sur OneDrive, Google Drive, GitHub, ni un autre cloud (cf. ADR-0006).
3. Test de restore tous les **6 mois** avec une des clés USB.

## Chiffrer un secret

### Création d'un nouveau secret

```powershell
# 1. Crée le fichier en clair (gitignored)
@"
postgres_password: monSuperPasswordIciDeQ
secret_key: aBcDeF1234567890aBcDeF1234567890
"@ | Out-File secrets/postgres.yaml -Encoding utf8

# 2. Chiffre vers .enc.yaml (commitable)
sops --encrypt secrets/postgres.yaml > secrets/postgres.enc.yaml

# 3. Supprime le fichier en clair
Remove-Item secrets/postgres.yaml
```

### Édition d'un secret existant

```powershell
# sops ouvre le déchiffré dans $EDITOR (notepad par défaut sur Windows)
sops secrets/postgres.enc.yaml
```

## Déchiffrer un secret

```powershell
# Vers stdout
sops --decrypt secrets/postgres.enc.yaml

# Via le helper script
.\scripts\decrypt_env.ps1 secrets/postgres.enc.yaml

# Vers un fichier .env.local pour docker compose
sops --decrypt secrets/postgres.enc.yaml > .env.local
docker compose --env-file .env.local up -d
Remove-Item .env.local  # ne JAMAIS laisser traîner
```

## Règles à respecter

- ❌ **JAMAIS** commit la clé privée `~/.age/hub.key`
- ❌ **JAMAIS** commit un fichier `.yaml` non chiffré dans `secrets/`
- ❌ **JAMAIS** sauvegarder la clé sur cloud (OneDrive, Drive, etc.)
- ✅ Le `.gitignore` du repo bloque `secrets/*.yaml` et n'autorise que `secrets/*.enc.yaml`
- ✅ Test de restore depuis USB tous les 6 mois
- ✅ Si tu changes de clé : `sops updatekeys secrets/*.enc.yaml`

## Liste des secrets attendus

À créer au fur et à mesure des intégrations :

| Fichier | Contenu | Utilisation |
|---|---|---|
| `secrets/postgres.enc.yaml` | `POSTGRES_PASSWORD`, `SECRET_KEY` | Base de la stack |
| `secrets/cloudflare.enc.yaml` | `CLOUDFLARE_TUNNEL_TOKEN`, `CF_ACCESS_AUDIENCE` | Tunnel + Access |
| `secrets/duckdns.enc.yaml` | `DUCKDNS_TOKEN` | Update DNS dynamique |
| `secrets/ntfy.enc.yaml` | URL topic ntfy avec auth | Notifications hub-ingest |
| `secrets/restic.enc.yaml` | Mot de passe restic + rclone OneDrive token | Backups |
| `secrets/google.enc.yaml` (Phase 3) | OAuth refresh tokens Gmail/Photos | Ingest Google |

## Mode rapide pour démarrer

Pour Phase 0 (avant Cloudflare/backup), seul `postgres.enc.yaml` est nécessaire :

```powershell
# 1. Init si pas déjà fait
.\scripts\init_secrets.ps1

# 2. Crée le secret postgres
$pgPwd = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
$secretKey = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
@"
POSTGRES_PASSWORD: $pgPwd
SECRET_KEY: $secretKey
"@ | Out-File secrets/postgres.yaml -Encoding utf8

sops --encrypt secrets/postgres.yaml > secrets/postgres.enc.yaml
Remove-Item secrets/postgres.yaml

# 3. Pour utiliser : déchiffre vers .env.local
.\scripts\decrypt_env.ps1 secrets/postgres.enc.yaml > .env.local
```

## Troubleshooting

### `sops: no key found`
La variable `SOPS_AGE_KEY_FILE` n'est pas set, ou le fichier n'existe pas.
```powershell
$env:SOPS_AGE_KEY_FILE = "$env:USERPROFILE\.age\hub.key"
```

### `sops: cannot read file: not encrypted`
Le fichier `.enc.yaml` est en fait en clair (probablement parce que tu l'as ouvert et que sops a échoué silencieusement). Re-encrypte :
```powershell
sops --encrypt fichier.yaml > fichier.enc.yaml
```

### Clé perdue après un crash disque
1. Récupère la clé depuis ta clé USB de backup
2. Copie vers `~/.age/hub.key`
3. Re-test : `sops --decrypt secrets/postgres.enc.yaml`

Si tu n'as pas de clé USB de backup et la clé est perdue :
- Tous les `secrets/*.enc.yaml` sont définitivement illisibles
- Tous les backups restic OneDrive sont définitivement illisibles
- Il faut **régénérer toute la stack** : nouvelle clé, nouveaux passwords, redémarrer Phase 0
