# hub-deploy — Contexte pour Claude Code

> **Avant de commencer, lis aussi :** `../../CLAUDE.md` (handoff projet global) et `~/.claude/CLAUDE.md` (profil Marc + règles).

## Rôle du repo

Infrastructure et déploiement du hub. Pas de code métier. Docker Compose + Caddy + Cloudflare Tunnel + scripts PowerShell + vault des secrets.

## Composants

| Service | Image | Port | Notes |
|---|---|---|---|
| postgres | pgvector/pgvector:pg16 | 5432 | DB principale + vector store |
| redis | redis:7-alpine | 6379 | Pour Celery/queues plus tard |
| hub-core | local build (../hub-core) | 8000 | Backend FastAPI |
| hub-frontend (Phase 1+) | local build (../hub-frontend) | 3000 | UI Next.js |
| caddy (Phase 1+) | caddy:2-alpine | 80 | Reverse proxy + routing versioning |
| cloudflared (Phase 0 fin) | cloudflare/cloudflared | - | Tunnel sortant |

**Important :** Ollama tourne en NATIF sur le host Windows (pas en Docker) pour profiter de la GPU RTX 5080. Les conteneurs y accèdent via `host.docker.internal:11434`.

## État actuel (2026-04-28)

✅ docker-compose.dev.yml prêt (postgres + redis + hub-core)
✅ Caddyfile prêt (avec template versioning d'apps)
✅ cloudflared/config.example.yml prêt
✅ secrets/README.md documenté pour age+sops
✅ Scripts PowerShell : `setup_windows.ps1`, `start_hub.ps1`, `stop_hub.ps1`, `healthcheck.ps1`
✅ docs/SETUP.md (10 étapes pas à pas)

❌ Pas testé en vrai
❌ Tunnel Cloudflare pas configuré (besoin Marc + UI Cloudflare)
❌ Cloudflare Access pas configuré
❌ Backup restic pas configuré

## Workflow de déploiement local

```powershell
cd C:\hub\hub-deploy
copy .env.example .env  # éditer
.\scripts\setup_windows.ps1  # vérif + pull modèles Ollama
.\scripts\start_hub.ps1      # docker compose up + healthcheck auto
```

## Conventions

- **Pas de secret en clair** — tout passe par age+sops
- `secrets/*.yaml` (non chiffré) blacklisté dans .gitignore
- `secrets/*.enc.yaml` (chiffré) commités OK
- Variables d'env sensibles → vault, pas dans `.env` versionné
- Scripts PowerShell : préfixés par `★` pour les messages info, `✓` succès, `❌` erreur, `⚠` warning

## TODO Phase 0 (final)

- [ ] Tester `docker compose -f docker-compose.dev.yml up -d` end-to-end
- [ ] Setup Cloudflare Tunnel : `cloudflared tunnel create marc-hub` + config.yml
- [ ] Setup Cloudflare Access (Zero Trust dashboard) avec policy email = marc.richard4@gmail.com + MFA TOTP
- [ ] Setup DuckDNS + script update IP
- [ ] Setup vault age+sops : `age-keygen` + `.sops.yaml`
- [ ] Setup backup restic vers OneDrive avec rclone
- [ ] Premier test backup + restore en réel
- [ ] Cron Windows Task Scheduler pour backups quotidiens 4h

## TODO Phase 1+

- [ ] Ajouter hub-frontend dans docker-compose
- [ ] Activer Caddy en mode prod
- [ ] Routing par versioning d'app dans Caddyfile (templates déjà là, à activer quand les apps existent)
- [ ] docker-compose.prod.yml avec cloudflared + caddy

## Règles spécifiques

- ❌ Ne JAMAIS commit un fichier `secrets/*.yaml` non chiffré
- ❌ Ne JAMAIS pusher `~/.cloudflared/<UUID>.json` (credentials tunnel)
- ❌ Ne JAMAIS supposer que Marc a installé un outil sans vérifier (utiliser `setup_windows.ps1` qui check)
- ✅ Tous les scripts PS1 doivent être idempotents
- ✅ Toujours faire `Test-Cmd` ou équivalent avant d'utiliser un binaire
- ✅ Erreur claire et actionnable si dépendance manque

## Bloquants externes connus

- **Cloudflare Tunnel free** demande parfois CB pour vérification — alternatives Tailscale Funnel
- **DuckDNS** sans Cloudflare DNS → utiliser quick tunnel (`xxx.trycloudflare.com`) à la place, qui change à chaque restart
- **OneDrive saturé** → fallback Backblaze B2 (~6$/TB/mo, mais Marc veut gratuit donc à éviter sauf urgence)

## Liens

- Setup pas à pas : `docs/SETUP.md`
- Master plan détaillé : `../../04_master_plan.md` (toutes les sous-étapes Phase 0)
- Vault README : `secrets/README.md`
