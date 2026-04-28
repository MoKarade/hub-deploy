# Setup du Personal Data Hub — guide pas à pas pour Marc

Suis ces étapes dans l'ordre. Chaque étape est checkable. Si une étape échoue, ne passe pas à la suivante.

## Étape 1 — Installer les outils prérequis

Ouvre **PowerShell en admin** et lance :

```powershell
winget install Docker.DockerDesktop
winget install Ollama.Ollama
winget install Git.Git
winget install Cloudflare.cloudflared
winget install FiloSottile.age
winget install Mozilla.sops
winget install GitHub.cli
```

Reboot ensuite (Docker Desktop demande WSL2, qui requiert un reboot).

**Check :** `docker --version`, `ollama --version`, `git --version` retournent tous une version.

---

## Étape 2 — Créer les 5 repos sur GitHub

Connecte-toi à GitHub avec gh CLI :

```powershell
gh auth login
```

Crée les repos PRIVÉS :

```powershell
gh repo create MoKarade/hub-core --private --description "Backend FastAPI du Personal Data Hub"
gh repo create MoKarade/hub-deploy --private --description "Infrastructure & docker-compose"
gh repo create MoKarade/hub-ingest --private --description "Workers d'ingestion data"
gh repo create MoKarade/hub-frontend --private --description "UI web (Next.js)"
gh repo create MoKarade/hub-docs --private --description "Documentation française"
```

---

## Étape 3 — Initialiser et pusher les repos déjà scaffolés

Tu as `hub-core` et `hub-deploy` déjà scaffolés en local dans `Hub perso\repos\`. On les pushe sur GitHub.

```powershell
cd "C:\Users\marcr\OneDrive\Documents\Claude\Projects\Hub perso\repos\hub-core"
git init
git add .
git commit -m "feat: initial scaffolding"
git branch -M main
git remote add origin https://github.com/MoKarade/hub-core.git
git push -u origin main
```

Idem pour hub-deploy :

```powershell
cd "C:\Users\marcr\OneDrive\Documents\Claude\Projects\Hub perso\repos\hub-deploy"
git init
git add .
git commit -m "feat: initial scaffolding"
git branch -M main
git remote add origin https://github.com/MoKarade/hub-deploy.git
git push -u origin main
```

---

## Étape 4 — Cloner les repos dans un dossier de travail

Crée un dossier dédié au projet, en dehors de OneDrive (pour éviter conflicts sync) :

```powershell
mkdir C:\hub
cd C:\hub
git clone https://github.com/MoKarade/hub-core.git
git clone https://github.com/MoKarade/hub-deploy.git
```

---

## Étape 5 — Configuration locale

```powershell
cd C:\hub\hub-deploy
copy .env.example .env
```

Édite `.env` avec un éditeur (notepad, VS Code) et remplace :

- `POSTGRES_PASSWORD` : génère un mot de passe fort
- `SECRET_KEY` : `python -c "import secrets; print(secrets.token_urlsafe(32))"` puis colle
- Les autres restent vides pour l'instant (Cloudflare/DuckDNS, on les remplira plus tard)

---

## Étape 6 — Setup Ollama et téléchargement des modèles

```powershell
cd C:\hub\hub-deploy
.\scripts\setup_windows.ps1
```

Le script va :
- Vérifier que tout est installé
- Créer `.env` si absent
- Vérifier que ta GPU NVIDIA est détectée
- Télécharger Qwen 2.5 14B (~9 GB) et nomic-embed-text (~270 MB)

**Durée :** 5-15 minutes selon ta connexion.

---

## Étape 7 — Lancer le hub

```powershell
.\scripts\start_hub.ps1
```

Le script va :
- Vérifier que Docker tourne
- Vérifier qu'Ollama tourne
- Lancer la stack docker-compose (Postgres + Redis + hub-core)
- Attendre que tout soit healthy

**Si tout marche, tu verras :**
```
✓ Hub up et healthy!

★ Personal Data Hub disponible :
  • API     : http://localhost:8000
  • Docs    : http://localhost:8000/docs
  • Health  : http://localhost:8000/v1/health
  • Ready   : http://localhost:8000/v1/ready (DB + Ollama)
```

Ouvre http://localhost:8000/docs dans ton navigateur — tu verras la doc OpenAPI auto-générée du hub.

Ouvre http://localhost:8000/v1/ready pour voir le status complet :
```json
{
  "status": "ok",
  "checks": {
    "database": {"status": "ok"},
    "ollama": {
      "status": "ok",
      "models_available": ["qwen2.5:14b-instruct", "nomic-embed-text"],
      "configured_model": "qwen2.5:14b-instruct"
    }
  }
}
```

---

## Étape 8 — Setup du tunnel Cloudflare (accès depuis l'extérieur)

À faire en Phase 0 final, après que le local marche.

```powershell
cloudflared tunnel login
# Ouvre une page web pour t'authentifier sur Cloudflare. Crée un compte gratuit si besoin.

cloudflared tunnel create marc-hub
# Note l'UUID retourné. Le credentials JSON est sauvé dans ~/.cloudflared/<UUID>.json

# Configure la route (nécessite un domaine sur Cloudflare).
# Si pas de domaine : on utilise pour l'instant le sous-domaine trycloudflare.com auto.
cloudflared tunnel run marc-hub
# Note l'URL https://xxxxx.trycloudflare.com retournée.
```

Tu peux aussi acheter un domaine .xyz ou .lol à 1-2$/an et le pointer sur Cloudflare DNS pour avoir une URL stable. **Mais pour rester 100% gratuit on s'en passe.**

---

## Étape 9 — Healthcheck depuis l'extérieur

Avec l'URL trycloudflare.com obtenue :

```
https://xxxxx.trycloudflare.com/v1/health
→ {"status":"ok"}
```

Si tu vois ça depuis ton téléphone (en 4G, hors WiFi maison), Phase 0 est ✓ TERMINÉE.

---

## Étape 10 — Sécurisation : Cloudflare Access

Avant que le hub soit vraiment exposé, on rajoute une couche d'auth pour que personne ne puisse y accéder à part toi.

Dans le dashboard Cloudflare Zero Trust (gratuit) :
- Créer une "Application" qui pointe sur ton domaine de tunnel
- Configurer "Access policy" : allow uniquement marc.richard4@gmail.com
- Activer MFA obligatoire (TOTP via Google Authenticator)

Une fois fait, n'importe qui qui ouvre l'URL devra passer par Google login + code TOTP.

---

## Troubleshooting

### "Port 5432 already in use"
Tu as déjà un Postgres local. Édite `docker-compose.dev.yml` et change `5432:5432` en `5433:5432`. Adapte aussi `DATABASE_URL` dans `.env`.

### Ollama ne voit pas la GPU
Vérifie `nvidia-smi`. Si rien : reboot, mets à jour les drivers NVIDIA, et relance Ollama. La RTX 5080 nécessite drivers récents.

### Le conteneur hub-core ne build pas
Vérifie que `hub-deploy` et `hub-core` sont dans le même dossier parent. Le compose fait `context: ../hub-core`.

### Docs en français à venir
- `RUNBOOK.md` : que faire si X tombe
- `BACKUP.md` : setup restic + tests de restore mensuels
