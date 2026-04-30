# Security checklist — Personal Data Hub

Audit complet réalisé 2026-04-30. Ce qui a été fixé ✅, ce qui reste à faire ⚠️.

---

## 🚨 Action URGENTE (à faire MAINTENANT)

### 1. Régénérer le client_secret Google OAuth

**Pourquoi** : le `client_secret` (`GOCSPX-CBk3...`) a été écrit dans `hub-deploy/.env`. Ce fichier est gitignoré (bon) MAIS il vit sur **Google Drive** (`G:\Mon disque\...`) qui synchronise dans le cloud Google. Donc le secret a été uploadé sur les serveurs Drive — risque résiduel non-négligeable.

**Action** :
1. Aller sur https://console.cloud.google.com/apis/credentials
2. Cliquer sur ton OAuth 2.0 Client ID `327399868142-...`
3. Bouton **"Reset secret"** (en haut)
4. Confirmer
5. Copier le nouveau secret
6. Mettre à jour :
   - `hub-secrets-vault.age` (vault chiffré OK pour Drive) — déchiffrer, modifier, re-chiffrer
   - `hub-deploy/.env` côté ton autre PC quand tu déploieras

L'ancien secret est révoqué automatiquement, donc même s'il a fuité il devient inutilisable.

### 2. Sortir `.env` de Google Drive

Le `.env` actuel à `G:\...\hub-deploy\.env` contient passwords + secrets en clair. Drive le synchronise → secrets cloud-uploadés.

**Solution recommandée** :
- Déplacer ce fichier vers `C:\Users\dessin14\.hub-secrets\hub-deploy.env` (hors Drive)
- Symbolic link OU `--env-file` flag dans docker-compose
- Le fichier reste local, pas de sync cloud

(Pour Phase 3 où tu déploies sur l'autre PC, créer le `.env` directement là, pas dans le Drive.)

---

## ✅ Fixes appliqués (audit 2026-04-30)

### Hub-core (Python backend)

| Issue | Fix | Commit |
|---|---|---|
| `secret_key="changeme"` accepté | `validate_for_production()` refuse au startup | (pending) |
| `client_secret` peut leak dans logs | `_scrub_oauth_error()` extrait juste l'`error` | (pending) |
| Refresh token logic incomplète | Préserve refresh + handle `invalid_grant` (révoque local) | (pending) |
| `user_email="unknown"` orphan | Échec propre du flow si userinfo fail | (pending) |
| `_STATE_STORE` mix naive/UTC | Tout en UTC | (pending) |
| `from datetime import UTC` redondant | Cleanup | (pending) |

### Hub-frontend (React/TS)

| Issue | Fix | Commit |
|---|---|---|
| Search history persiste `rows` (data sensibles) | Strip `rows` avant `localStorage.setItem` | (pending) |
| `console.error` monkey-patch global | Retiré, `onError` natif APIProvider | (pending) |
| Pas de CSRF token | Header `X-Hub-Client: web` (déclenche preflight) | (pending) |
| Race condition PasswordChecker | `AbortController` + check `signal.aborted` | (pending) |
| `parseFloat(NaN)` GPS coords | Filter `Number.isFinite` + range validation | (pending) |
| `parseInt(c, 10)` peut être NaN | Guard `Number.isFinite(count)` | (pending) |

### Hub-deploy (infra)

| Issue | Fix | Commit |
|---|---|---|
| Postgres bind `0.0.0.0` (LAN-accessible) | `127.0.0.1:5432:5432` | (pending) |
| Redis bind `0.0.0.0` (LAN-accessible) | `127.0.0.1:6379:6379` | (pending) |
| Fallbacks `:-hubpass` `:-hub` | `:?required` | (pending) |
| Quick tunnel backend sans warning | Flag `-IUnderstandThisIsPublic` requis | (pending) |
| OAuth env vars manquaient dans compose | Ajoutées | (pending) |

---

## ⚠️ Limitations connues (acceptables pour usage perso)

### Single-worker uniquement

`_STATE_STORE` (PKCE state OAuth) est un dict in-memory du process. Si tu lances `uvicorn --workers >1`, les states ne se partagent pas → callbacks OAuth peuvent fail. **Solution future** : Redis ou table DB. Pour usage perso single-worker, OK.

### Pas de Cloudflare Access middleware côté hub-core

Les endpoints `/v1/oauth/*`, `/v1/finance/*`, `/v1/locations/*` ne valident pas le JWT `Cf-Access-Jwt-Assertion`. Si tu mets juste un Named Tunnel sans Access Policy, l'API est exposée. **Solution** : configurer Cloudflare Access (Niveau 3 dans `CLOUDFLARE-TUNNEL.md`) qui bloque AVANT que les requêtes atteignent le hub.

Une validation côté backend est un futur ajout (defense-in-depth).

### `.env.example` peut survivre

Si `cp .env.example .env` puis Marc oublie de modifier, `SECRET_KEY=changeme-...` passe. **Mitigé** maintenant par `validate_for_production()` qui refuse au startup.

---

## 🔐 Bonnes pratiques (rappel)

1. **Vault age** = source de vérité pour les secrets sensibles. Tout passe par là.
2. **`.env` jamais sur Drive** (cf. action #2 ci-dessus)
3. **Régénérer un secret après fuite suspectée** (cf. action #1)
4. **Backup clé privée age** (USB / password manager) — sans elle, vault inaccessible
5. **Cloudflare Access en Niveau 3** dès qu'on déploie sur Internet
6. **Multi-worker = Redis** (pas avant)
7. **Pas de credentials dans les commits** — vérifier avec `git grep -E "AIzaSy[A-Za-z0-9_-]{30,}|GOCSPX-[A-Za-z0-9_-]{20,}"`

---

## 📅 Prochaine review

Après chaque ajout de feature majeur, refaire un audit ciblé. Surtout :
- Phase 3 ingest (Gmail / Photos / Drive) → vérifier scopes minimum, pas de sur-fetch
- Cloudflare Tunnel deployment → tester que /v1/* refuse sans header CF
- Multi-user (improbable mais) → revoir `OAuthToken.user_email` pour vrai user_id
