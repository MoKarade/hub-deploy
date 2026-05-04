# Secrets hors de Google Drive

## Le risque

Le repo `hub-perso` vit dans `G:\Mon disque\PERSO & LOISIRS\...` (Google Drive sync).
**Tout** ce qui est dans ce dossier est uploade vers Google, peu importe le
`.gitignore`. Cela inclut les fichiers `.env` qui contiennent :

- `POSTGRES_PASSWORD`
- `RESTIC_PASSWORD` (cle de chiffrement des backups)
- `DUCKDNS_TOKEN`
- `GOOGLE_OAUTH_CLIENT_SECRET`
- `CLOUDFLARE_TUNNEL_TOKEN`
- `SECRET_KEY` (FastAPI)

`.gitignore` ne protege **que de Git**, pas de Google Drive.

## La solution

Sortir les `.env` de Drive et y creer un symlink :

```
G:\Mon disque\...\hub-deploy\.env  -->  C:\Users\dessin14\.hub-secrets\hub-deploy.env
G:\Mon disque\...\hub-core\.env    -->  C:\Users\dessin14\.hub-secrets\hub-core.env
```

Le symlink lui-meme est synchronise par Drive mais Google ne voit que le
pointeur, pas le contenu reel du secret.

## Comment migrer

Lance le script (necessite admin OU Developer Mode active dans Settings) :

```powershell
cd "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-deploy"
.\scripts\migrate-env-out-of-drive.ps1
```

Le script est idempotent : tu peux le relancer sans risque.

## Activer Developer Mode (sans admin)

Pour creer des symlinks sans droits admin :

1. Settings > Privacy & security > For developers
2. Active "Developer Mode"
3. Relance le script

## Rotation des secrets compromis

Si un `.env` a ete dans Drive avant la migration, **il faut considerer les
secrets comme compromis** et les rotationner :

### DUCKDNS_TOKEN

1. Va sur <https://www.duckdns.org/> -> connexion
2. Bouton "recreate token" en haut de la page
3. Mets a jour `DUCKDNS_TOKEN=...` dans `~/.hub-secrets/hub-deploy.env`
4. Test : `.\scripts\update-duckdns.ps1`

### GOOGLE_OAUTH_CLIENT_SECRET

1. <https://console.cloud.google.com/apis/credentials>
2. Selectionne le client OAuth -> "Reset Client Secret"
3. Mets a jour `GOOGLE_OAUTH_CLIENT_SECRET=...` dans `~/.hub-secrets/hub-core.env`
4. **Note** : tous les refresh_tokens existants deviennent invalides ; refais
   le flow OAuth pour Gmail / Calendar / Photos / Fit.

### RESTIC_PASSWORD

`restic key passwd` permet de changer le mot de passe sans tout reuploader :

```powershell
$env:RESTIC_REPOSITORY = "C:\Users\dessin14\OneDrive\hub-backup"
$env:RESTIC_PASSWORD = "<ancien>"
restic key passwd
# Tape le nouveau mdp
```

Puis mets a jour `RESTIC_PASSWORD=...` dans `~/.hub-secrets/hub-deploy.env`.

### CLOUDFLARE_TUNNEL_TOKEN

1. <https://one.dash.cloudflare.com/> -> Networks -> Tunnels
2. Selectionne le tunnel -> Configure -> "Refresh token"
3. Mets a jour `CLOUDFLARE_TUNNEL_TOKEN=...`
