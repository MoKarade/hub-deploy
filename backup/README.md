# Backups — restic + rclone OneDrive

Backups quotidiens chiffrés du hub (DB Postgres + raw_events + secrets) vers OneDrive personnel via [restic](https://restic.net/) + [rclone](https://rclone.org/).

Voir [ADR-0006](../../hub-docs/decisions/0006-age-sops-vs-vault.md) pour la stratégie de chiffrement.

## Architecture du backup

```
PC Marc                                Cloud
─────────                              ─────
Postgres ──pg_dump──┐
                    ├─→ restic ──TLS──→ rclone OneDrive
raw_events/ ────────┤    (chiffrement
                    │     client-side)
inbox/processed ────┤
                    │
secrets/*.enc.yaml ─┘    (déjà chiffré
                          mais on backup
                          quand même)
```

**Chiffrement double** :
1. `restic` chiffre les données avec sa clé interne (AES-256)
2. La clé restic est elle-même protégée par un mot de passe stocké en chiffré dans `secrets/restic.enc.yaml` (sops)
3. OneDrive ne voit que le résultat chiffré

**Sans la clé `~/.age/hub.key`** (cf. ADR-0006), même si quelqu'un vole l'OneDrive de Marc, il ne peut rien lire.

## Setup initial

### 1. Installer les outils

```powershell
winget install restic.restic
winget install Rclone.Rclone
```

### 2. Configurer rclone vers OneDrive

```powershell
rclone config
# Suis l'assistant :
#   - n (new remote)
#   - name : onedrive
#   - storage : 27 (Microsoft OneDrive)
#   - client_id : (vide, défaut)
#   - client_secret : (vide, défaut)
#   - region : 1 (Microsoft Cloud Global)
#   - drive_type : 1 (OneDrive Personal)
#   - choose root : 1 (Personal)
#   - y (yes, configure)
# Puis browser auth.

# Test :
rclone lsd onedrive:
# → doit lister les dossiers OneDrive de Marc
```

### 3. Créer le repo restic

```powershell
# Génère un mot de passe restic costaud (32 chars)
$resticPwd = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | ForEach-Object { [char]$_ })

# Sauvegarde-le dans secrets/restic.enc.yaml (sops)
@"
RESTIC_PASSWORD: $resticPwd
RESTIC_REPOSITORY: rclone:onedrive:backups/hub
"@ | Out-File secrets/restic.yaml -Encoding utf8
sops --encrypt secrets/restic.yaml > secrets/restic.enc.yaml
Remove-Item secrets/restic.yaml

# Initialise le repo restic
$env:RESTIC_PASSWORD = $resticPwd
$env:RESTIC_REPOSITORY = "rclone:onedrive:backups/hub"
restic init

# → "created restic repository xxx at rclone:onedrive:backups/hub"
```

### 4. Premier backup

```powershell
.\backup\scripts\backup.ps1
# → snapshot id xxxxx
```

### 5. Premier test de restore (CRITIQUE)

```powershell
mkdir C:\hub-restore-test
.\backup\scripts\restore.ps1 -Target C:\hub-restore-test
# → vérifie que C:\hub-restore-test contient bien le dump SQL + les raw_events
```

Si le restore marche, le backup est validé.

### 6. Schedule quotidien (Windows Task Scheduler)

```powershell
$trigger = New-ScheduledTaskTrigger -Daily -At 4am
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\hub\hub-deploy\backup\scripts\backup.ps1"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U
Register-ScheduledTask -TaskName "HubBackup" -Trigger $trigger -Action $action -Principal $principal -Description "Personal Data Hub - daily restic backup"
```

Vérifier :
```powershell
Get-ScheduledTask -TaskName HubBackup
```

## Scripts disponibles

| Script | Rôle |
|---|---|
| `backup/scripts/backup.ps1` | Snapshot complet (pg_dump + raw_events + secrets chiffrés) |
| `backup/scripts/restore.ps1` | Restore d'un snapshot (latest par défaut) |
| `backup/scripts/verify.ps1` | `restic check` — vérifie l'intégrité du repo |

## Politique de rétention

Configurée dans `backup.ps1` après chaque snapshot :

```
restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --prune
```

Garde :
- 7 derniers daily
- 4 derniers weekly
- 12 derniers monthly

Soit ~23 snapshots stockés en permanence.

## Test de restore mensuel

**Obligatoire** (cf. ADR-0006) : tester le restore tous les mois.

```powershell
mkdir C:\hub-restore-monthly-test
.\backup\scripts\restore.ps1 -Target C:\hub-restore-monthly-test -Snapshot latest
.\backup\scripts\verify.ps1
Remove-Item -Recurse -Force C:\hub-restore-monthly-test
```

Si l'un des deux échoue : ne pas attendre le prochain test, fix immédiatement.

## Surveillance

Le script `backup.ps1` envoie une notification ntfy (success ou failure) à la fin. Marc reçoit la notif sur son téléphone.

Si pas de notif à 04h05 du matin → vérifier manuellement.

## Restoration complète après catastrophe

Voir aussi `hub-docs/07-runbook.md` (section "Procédure de restoration complète").

```powershell
# 1. Récupère ta clé age depuis ta clé USB
copy F:\backup-key\hub.key $env:USERPROFILE\.age\hub.key

# 2. Setup rclone vers OneDrive (cf. step 2 ci-dessus)
rclone config

# 3. Récupère le password restic (chiffré dans secrets/restic.enc.yaml)
.\scripts\decrypt_env.ps1 secrets/restic.enc.yaml > .env.restic

# 4. Restore vers C:\hub-restored
$env:RESTIC_REPOSITORY = "rclone:onedrive:backups/hub"
$env:RESTIC_PASSWORD = (Get-Content .env.restic | Select-String "RESTIC_PASSWORD" | ForEach-Object { ($_ -split ': ')[1] })
restic restore latest --target C:\hub-restored

# 5. Restore le pg_dump dans la nouvelle DB Postgres
docker compose -f docker-compose.dev.yml up -d postgres
docker exec -i hub-prod-postgres-1 psql -U hub hubdb < C:\hub-restored\db.sql

# 6. Lance la stack
.\scripts\start_hub.ps1
```

RTO target : 4-8h.

## Troubleshooting

### "rclone: failed to make remote: HTTP 401"
Le token OneDrive est expiré. `rclone config reconnect onedrive:`.

### "restic: repository contains pack errors"
`restic check --read-data` pour validation profonde. Si vraiment cassé, restore le repo OneDrive depuis un backup OneDrive antérieur (Microsoft garde 30 jours de file history).

### "OneDrive plein"
Vérifier `restic stats` — possiblement la rétention ne nettoie pas. Forcer `restic prune`.
Si vraiment plein → fallback Backblaze B2 (~6$/TB/mois). Modifier `RESTIC_REPOSITORY` en conséquence.
