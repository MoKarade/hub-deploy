# Setup Cloudflare Tunnel

Étapes pour activer l'accès externe au hub via Cloudflare Tunnel + Access (cf. ADR-0005).

## 1 — Créer un compte Cloudflare gratuit

https://dash.cloudflare.com/sign-up — gratuit. Ajoute un domaine (DuckDNS suffit pour le free tier, ou achète un domaine .xyz à 1$/an).

## 2 — Installer cloudflared (côté host Windows)

```powershell
winget install --id Cloudflare.cloudflared
```

## 3 — Login et création du tunnel

```powershell
cloudflared tunnel login
# Ouvre une page web : choisis ton domaine → autorise.
# Le credentials JSON est sauvé dans %USERPROFILE%\.cloudflared\<UUID>.json

cloudflared tunnel create marc-hub
# Note le tunnel UUID + chemin credentials.json affichés.
```

## 4 — Configurer le routage (mode dashboard, recommandé)

Plus simple que `config.yml` : tout se fait via Cloudflare Zero Trust dashboard.

1. https://one.dash.cloudflare.com/ → Networks → Tunnels
2. Sélectionne `marc-hub`
3. Onglet "Public Hostnames" → Add a public hostname :
   - **Subdomain** : laisse vide (ou `hub`)
   - **Domain** : ton domaine
   - **Service** : `HTTP` → `caddy:80` (ou `localhost:80` si pas en docker)
4. Save

Cloudflare te donne ensuite un **TOKEN** à passer au conteneur cloudflared :
   - Networks → Tunnels → marc-hub → Configure → Install connector
   - Copie le token affiché → met dans `.env` :
     ```
     CLOUDFLARE_TUNNEL_TOKEN=eyJhIj...
     ```

## 5 — Configurer Cloudflare Access (auth Google + MFA)

1. Zero Trust dashboard → Access → Applications → Add application → Self-hosted
2. **Application domain** : `marc-hub.duckdns.org` (le hostname configuré au step 4)
3. **Identity providers** : ajoute Google (suit l'assistant pour OAuth)
4. **Policies** :
   - Name : "Marc only"
   - Action : Allow
   - Include : Emails → `marc.richard4@gmail.com`
   - Require : MFA → TOTP
5. Save

À partir de maintenant, toute requête vers `marc-hub.duckdns.org` doit passer par Google login + TOTP.

## 6 — Lancer cloudflared (mode docker compose)

```powershell
cd C:\hub\hub-deploy
docker compose -f docker-compose.prod.yml --env-file .env up -d cloudflared
docker compose -f docker-compose.prod.yml logs -f cloudflared
```

Tu dois voir :
```
INF Connection registered ... locations=[YUL YYZ]
```

## 7 — Test depuis l'extérieur

Depuis ton téléphone en 4G (pas en WiFi maison) :

```
https://marc-hub.duckdns.org/v1/health
```

→ Login Google, code TOTP, puis tu vois `{"status":"ok"}`.

## Mode standalone (sans docker)

Si tu préfères faire tourner cloudflared comme service Windows :

```powershell
# Copie config.example.yml en config.yml
cp config.example.yml $env:USERPROFILE\.cloudflared\config.yml
# édite avec ton UUID

# Install comme service Windows
cloudflared.exe service install
```

## Fallback si Cloudflare ferme le free tier

Voir ADR-0005 : migration prête vers Tailscale Funnel en ~4h.

## Troubleshooting

### "Tunnel not found"
Vérifie que le `CLOUDFLARE_TUNNEL_TOKEN` dans `.env` correspond au tunnel actuel (les tokens deviennent invalides si tu delete/recreate le tunnel).

### "502 Bad Gateway" depuis l'extérieur
Caddy ne répond pas. Check `docker compose logs caddy` puis `docker compose logs hub-core`.

### "Cloudflare Access blocked you"
Re-auth Google. Si reset TOTP par erreur : depuis `localhost` (chez toi) tu as toujours accès, et tu peux reset la policy depuis le dashboard.
