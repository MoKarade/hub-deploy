# Phase 0 fin — Déploiement complet (sur le PC de Marc)

Cette doc explique les **étapes one-time** pour finaliser la Phase 0 sur le vrai PC (l'autre PC, pas celui de dev). À faire une fois Docker installé là-bas.

## ✅ Ce qui est livré (code-prêt)

| Composant | Status | Fichier |
|---|---|---|
| Cloudflare Tunnel scripts | ✅ | `scripts/start-tunnel.ps1`, `cloudflared/config.example.yml` |
| Cloudflare Access middleware | ✅ | `hub-core/src/core/cf_access.py` (validation JWT) |
| Backup chiffré restic | ✅ | `scripts/backup-hub.ps1` |
| Vault age + scripts | ✅ | `scripts/decrypt-vault.ps1`, `backup-age-key-to-drive.ps1` |
| Pre-push CI hooks | ✅ | `scripts/install-pre-push-hooks.ps1` |

## 🚧 Étapes manuelles (une fois)

### 1. Setup Cloudflare Tunnel + Access (15 min)

Voir `docs/CLOUDFLARE-TUNNEL.md` pour les détails.

**Résumé** :
1. `cloudflared tunnel login` (auth via browser)
2. `cloudflared tunnel create marc-hub`
3. `cloudflared tunnel route dns marc-hub hub.tondomaine.com`
4. Copier `cloudflared/config.example.yml` → `config.yml`, remplir UUID
5. Lancer `.\scripts\start-tunnel.ps1 -Mode named`
6. Dans Cloudflare Zero Trust dashboard :
   - Settings → Authentication → ajouter Google comme IdP
   - Access → Applications → Add → policy email = `marc.richard4@gmail.com`
7. Récupérer le **AUD tag** (sur la page de l'application)
8. Mettre dans `hub-deploy/.env` :
   ```
   CF_ACCESS_TEAM_DOMAIN=tonteam.cloudflareaccess.com
   CF_ACCESS_AUDIENCE=<AUD-tag>
   ```
9. Restart hub-core → middleware s'active automatiquement

### 2. Setup backup restic vers Drive (5 min)

```powershell
# Une fois (init du repo restic)
.\scripts\backup-hub.ps1 -Init

# À chaque backup (manuel ou cron)
.\scripts\backup-hub.ps1
```

**Sauvegarde** :
- Postgres dump (transactions, GPS, oauth tokens)
- `raw_events/` (event sourcing immutable)
- `inbox/` (CSV/PDF en attente)
- `hub-deploy/.env` (secrets, déjà chiffrés age dans le vault aussi)

**Tout est chiffré par restic** avec un password (différent du master Marc).
Le repo est sur Drive (`G:\...\Hub perso\backups-restic\`) → backup multi-PC automatique.

### 3. Cron quotidien Windows (5 min)

```powershell
# Crée une tâche planifiée à 4h du matin
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File 'G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-deploy\scripts\backup-hub.ps1' -Quiet"
$trigger = New-ScheduledTaskTrigger -Daily -At 4am
Register-ScheduledTask -TaskName "Hub backup" -Action $action -Trigger $trigger
```

⚠️ Stocker `$env:RESTIC_PASSWORD` dans un script wrapper si automation.

### 4. Validation end-to-end

1. Va sur https://hub.tondomaine.com depuis ton téléphone
2. Cloudflare Access intercepte → demande login Google
3. Tu autorises avec ton email → laissé passer
4. Ton hub s'affiche
5. Tu peux poser des questions IA, voir tes data, etc.

Si quelqu'un d'autre tente la même URL → bloqué par Cloudflare Access.

## 📋 Checklist déploiement

- [ ] Docker Desktop installé sur l'autre PC
- [ ] `git clone` des 5 repos
- [ ] `cp .env.example .env` + remplir avec vrais secrets (déchiffrer le vault)
- [ ] Vault age key restored (`restore-age-key-from-drive.ps1`)
- [ ] `.\scripts\start_hub.ps1` → backend live
- [ ] `npm install` + `npm run build` du frontend
- [ ] Cloudflare Tunnel setup (étape 1)
- [ ] Cloudflare Access policy (étape 1.6)
- [ ] `CF_ACCESS_TEAM_DOMAIN` + `CF_ACCESS_AUDIENCE` dans .env
- [ ] Restart hub-core (middleware actif)
- [ ] Backup restic init (étape 2)
- [ ] Tâche planifiée Windows (étape 3)
- [ ] Test depuis téléphone (étape 4)

## ✅ Phase 0 terminée

À ce stade :
- Hub accessible depuis n'importe où via `https://hub.tondomaine.com`
- Auth obligatoire (login Google + MFA Cloudflare Access)
- Backup chiffré quotidien sur Drive (et donc multi-PC)
- Tous les secrets chiffrés (vault age + .env Drive sync)
- CI verts sur les 5 repos (pre-push hooks)

Phase 1+ peut démarrer (ingest banking + IA basique).
