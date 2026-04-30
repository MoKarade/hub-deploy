# Security checklist — Personal Data Hub

Audit complet réalisé 2026-04-30. Ce qui a été fixé ✅, ce qui reste à faire ⚠️.

---

## 🎯 Décision Marc 2026-04-30 : tout sur Drive (accepté)

Marc a explicitement choisi de garder **tous les secrets sur Drive** — vault chiffré ET `.env` en clair. Préférence pratique > minimisation absolue du risque cloud-sync.

**Ce qui reste sécurisé** :
- ✅ `hub-secrets-vault.age` chiffré (Fernet via age key) — OK sur Drive
- ✅ Clé privée age `C:\Users\dessin14\.hub-secrets\age-key.txt` — **JAMAIS sur Drive** (sinon vault déverrouillable)
- ✅ Aucun secret en clair dans Git (toujours `.env*` + `*.age` gitignored)

**Ce qui transite Drive en clair** :
- ⚠️ `hub-deploy/.env` : POSTGRES_PASSWORD, SECRET_KEY, GOOGLE_OAUTH_CLIENT_SECRET
- Marc l'a accepté. Risque résiduel : si compte Google Drive compromis, secrets accessibles. Mitigation : compte Marc avec MFA + password fort.

**Backup obligatoire** :
- 🔒 La clé privée age — sans elle vault perdu si crash disque
- → USB drive + password manager (1Password / Bitwarden / KeePass)

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
