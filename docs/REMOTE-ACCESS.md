# Accès distant au Hub perso

> Guide pour accéder à ton hub depuis l'extérieur de chez toi (téléphone, autre ordi).

Tu as **2 options principales**. Choisis-en une.

---

## Option A : Cloudflare Tunnel ⭐ recommandé

**Avantages** :
- ✅ Pas besoin d'ouvrir des ports sur ton routeur
- ✅ HTTPS automatique
- ✅ Auth Cloudflare Access (login Google obligatoire avant d'accéder)
- ✅ Protection DDoS gratuite
- ✅ URL stable `hub.tondomaine.com`

**Inconvénients** :
- Faut un nom de domaine (~12$/an, optionnel mais recommandé pour URL propre)
- Setup initial ~15 min via dashboard Cloudflare

**Setup** : voir `docs/CLOUDFLARE-TUNNEL.md`

**Usage** :
```powershell
.\scripts\start-tunnel.ps1 -Mode named
```

Sans nom de domaine, tu peux utiliser le **Quick Tunnel** (URL temporaire `xxx.trycloudflare.com`, change à chaque restart) :

```powershell
.\scripts\start-tunnel.ps1 -Mode quick
```

⚠️ **Quick tunnel = pas d'auth, URL publique**. Quiconque la connaît a accès. À utiliser uniquement pour test ponctuel.

---

## Option B : DuckDNS + port forwarding

**Avantages** :
- ✅ Gratuit et simple
- ✅ URL stable `marc-hub.duckdns.org`

**Inconvénients** :
- ❌ Faut ouvrir port 80/443 sur ton routeur (sécurité moins bonne)
- ❌ Pas d'auth automatique (à configurer via Caddy + basic auth ou similaire)
- ❌ Ton IP publique est exposée

**Setup** :
1. Crée un compte gratuit sur https://www.duckdns.org/
2. Note ton **token** + **sous-domaine** (ex: `marc-hub`)
3. Édite `hub-deploy/.env` :
   ```
   DUCKDNS_TOKEN=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   DUCKDNS_DOMAIN=marc-hub
   ```
4. Test l'update manuel :
   ```powershell
   .\scripts\update-duckdns.ps1
   ```
5. Programme l'update auto toutes les 5 min :
   ```powershell
   .\scripts\install-duckdns-task.ps1
   ```
6. Configure le port forwarding sur ton routeur :
   - Port externe `80` → IP locale de ton PC, port `80`
   - (Idem pour `443` si HTTPS via Caddy)

**Usage** : `https://marc-hub.duckdns.org` accessible publiquement.

---

## Recommandation

**Si tu as 12$/an pour un domaine** → Option A (Cloudflare Tunnel + Access). C'est plus secure et stable.

**Si tu veux 100% gratuit** → Option A en mode Quick (URL temporaire pour tests) ou Option B (DuckDNS, mais avec auth Caddy basic).

**Pour usage perso quotidien sur téléphone** → Option A en mode Named avec Cloudflare Access.
