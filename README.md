# hub-deploy

Infrastructure et déploiement du Personal Data Hub.
Tout ce qui fait tourner le hub sur le PC Windows de Marc — pas de code métier, juste de la conf.

## Composants

- **PostgreSQL 16 + pgvector** — DB principale et vector store pour le RAG
- **Ollama** — runtime LLM local (Qwen 2.5 14B Instruct + nomic-embed-text)
- **hub-core** — backend FastAPI (image construite depuis le repo `hub-core`)
- **hub-frontend** — UI web (image construite depuis le repo `hub-frontend`, Phase 1+)
- **Caddy** — reverse proxy, TLS auto, routing par version d'app
- **cloudflared** — tunnel Cloudflare → expose le hub depuis l'extérieur
- **Backup restic** — backup chiffré quotidien vers OneDrive + disque externe

## Prérequis sur Windows

```powershell
# 1. Docker Desktop avec WSL2 backend
winget install Docker.DockerDesktop

# 2. Ollama (gère la GPU NVIDIA RTX 5080 nativement)
winget install Ollama.Ollama

# 3. cloudflared
winget install --id Cloudflare.cloudflared

# 4. age + sops (vault de secrets)
winget install FiloSottile.age
winget install Mozilla.sops

# 5. (optionnel) restic pour backups
winget install restic.restic
```

## Setup initial

Suivre `docs/SETUP.md` (à venir) ou en résumé :

```powershell
# 1. Clone tous les repos dans un dossier parent
git clone https://github.com/MoKarade/hub-core.git
git clone https://github.com/MoKarade/hub-frontend.git
git clone https://github.com/MoKarade/hub-ingest.git
git clone https://github.com/MoKarade/hub-deploy.git

# 2. Dans hub-deploy
cd hub-deploy
copy .env.example .env
# édite .env avec tes valeurs

# 3. Génère ta clé age et provisionne les secrets
.\scripts\init_secrets.ps1

# 4. Pull les modèles Ollama
ollama pull qwen2.5:14b-instruct
ollama pull nomic-embed-text

# 5. Lance la stack
docker compose -f docker-compose.dev.yml up -d

# 6. Vérifie
curl http://localhost:8000/v1/health
curl http://localhost:8000/v1/ready
```

## Structure

```
hub-deploy/
├── docker-compose.dev.yml          # stack complète en local
├── docker-compose.prod.yml         # avec cloudflared + caddy en plus
├── .env.example
├── caddy/
│   └── Caddyfile                   # routing /apps/.../v* → ports
├── cloudflared/
│   └── config.example.yml          # template de config tunnel
├── secrets/
│   └── README.md                   # comment chiffrer/déchiffrer avec sops
├── backup/
│   ├── restic-config.toml.example
│   └── scripts/                    # backup, restore, verify
├── scripts/
│   ├── setup_windows.ps1
│   ├── start_hub.ps1
│   ├── stop_hub.ps1
│   ├── healthcheck.ps1
│   └── init_secrets.ps1
└── docs/
    ├── SETUP.md
    └── RUNBOOK.md
```

## URLs locales (en dev)

- Hub API : http://localhost:8000
- Docs API : http://localhost:8000/docs
- PostgreSQL : `postgres://hub:hubpass@localhost:5432/hubdb`
- Ollama : http://localhost:11434
- Caddy (Phase 1+) : http://localhost (route vers hub-frontend)

## URLs publiques (Phase 0+ avec tunnel)

- Hub principal : https://marc-hub.duckdns.org (à configurer dans Cloudflare Tunnel)
- Auth : Cloudflare Access (Google login + MFA)
