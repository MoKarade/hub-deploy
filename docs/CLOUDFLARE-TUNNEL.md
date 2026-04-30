# Cloudflare Tunnel — exposer le hub sur Internet

Permet d'accéder au hub depuis ton téléphone (ou n'importe où) **sans ouvrir de port** sur ton routeur. Le tunnel sortant est créé par `cloudflared` qui tourne sur ton PC.

3 niveaux de setup, du plus simple au plus sécurisé :

---

## 🚀 Niveau 1 — Quick Tunnel (test rapide, pas sécurisé)

**Use case** : tester un truc 5 minutes depuis ton téléphone, sans setup.

```powershell
cd "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-deploy"
.\scripts\start-tunnel.ps1
```

Cloudflared affiche une URL `https://<random-words>.trycloudflare.com` — c'est ton hub, accessible de n'importe où.

⚠️ **PAS DE PROTECTION** : l'URL est publique. N'importe qui qui la trouve a accès à toutes tes data. **Ferme le tunnel (Ctrl+C) dès que tu as fini.** Ne JAMAIS partager cette URL.

L'URL change à chaque restart → pas pratique pour usage régulier.

---

## 🔒 Niveau 2 — Named Tunnel (URL stable, recommandé)

**Use case** : URL stable `hub.tondomaine.com` que tu mets en raccourci sur ton téléphone, accessible 24/7.

### Setup une fois

1. **Créer un compte Cloudflare gratuit** : https://dash.cloudflare.com/sign-up

2. **Authentifier cloudflared** sur ce PC :
   ```powershell
   & "C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel login
   ```
   Ouvre un browser, connecte-toi, autorise. Crée `~/.cloudflared/cert.pem`.

3. **Acheter ou utiliser un domaine** dans Cloudflare. Options :
   - **Acheter via Cloudflare** : ~10 USD/an pour `.com`, ~5 USD pour `.fr`
   - **Domaine existant** : ajoute-le dans Cloudflare → change tes nameservers → propagation 24h
   - **Alternative gratuite** : `.duckdns.org` mais nécessite manip DNS plus complexe

4. **Créer le tunnel** :
   ```powershell
   & "C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel create marc-hub
   ```
   Génère un fichier `~/.cloudflared/<UUID>.json` avec les credentials.

5. **Créer le DNS record** :
   ```powershell
   & "C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel route dns marc-hub hub.tondomaine.com
   ```

6. **Copier la config example** :
   ```powershell
   copy hub-deploy\cloudflared\config.example.yml hub-deploy\cloudflared\config.yml
   ```
   Édite `config.yml` :
   ```yaml
   tunnel: <UUID-du-tunnel>
   credentials-file: C:\Users\dessin14\.cloudflared\<UUID>.json

   ingress:
     - hostname: hub.tondomaine.com
       service: http://localhost:3000
     - hostname: api.tondomaine.com
       service: http://localhost:8000
     - service: http_status:404
   ```

7. **Lancer le tunnel** :
   ```powershell
   .\scripts\start-tunnel.ps1 -Mode named
   ```

8. **Tester** : ouvre `https://hub.tondomaine.com` sur ton téléphone → tu vois le hub.

⚠️ **Toujours pas d'auth** : si quelqu'un connaît ton URL, il accède à tout. **Niveau 3 obligatoire pour usage long-terme.**

---

## 🛡️ Niveau 3 — Cloudflare Access (auth Google obligatoire)

**Use case** : seul TOI peut accéder au hub, après login Google + MFA. Le standard zero-trust pour expose un service perso.

### Setup une fois (15 min)

1. Va dans [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
   - Plan **Free** suffit (jusqu'à 50 users)

2. **Settings → Authentication → Login methods** : ajoute **Google** comme identity provider
   - Crée un nouveau OAuth client dans Google Cloud Console (différent de celui du hub-core !) ou réutilise
   - Coller client_id + secret dans Cloudflare

3. **Access → Applications → Add an application → Self-hosted**
   - **Application domain** : `hub.tondomaine.com`
   - **Session duration** : 24 hours (ajustable)
   - **Identity providers** : Google uniquement

4. **Add a policy** :
   - **Action** : Allow
   - **Include** : Email = `marc.richard4@gmail.com`
   - (Optionnel) Require MFA via Google (TOTP authenticator)

5. **Sauvegarder**.

Maintenant : quand tu vas sur `https://hub.tondomaine.com`, Cloudflare intercepte avant ton hub, demande login Google. Si email = ton email → laisse passer. Sinon → accès refusé.

⚠️ **L'URL n'est plus accessible publiquement**. Le hub-core n'a pas besoin de connaître Cloudflare Access (transparent).

### Validation des JWT côté hub-core (optionnel mais recommandé)

Cloudflare Access ajoute un header `Cf-Access-Jwt-Assertion` à chaque requête qui passe. Le backend peut valider ce JWT pour s'assurer qu'il vient bien de Cloudflare (defense-in-depth contre bypass).

Variables env dans hub-deploy/.env :
```
CF_ACCESS_TEAM_DOMAIN=tonteam.cloudflareaccess.com
CF_ACCESS_AUDIENCE=<audience-tag-du-tunnel>
```

(Implémentation middleware dans hub-core = TODO Phase 0 fin)

---

## 📊 Comparaison des 3 niveaux

| | Quick | Named | Named + Access |
|---|---|---|---|
| **Setup** | 0 min | 15 min (1x) | +15 min (1x) |
| **Coût** | Gratuit | ~10 USD/an (domaine) | Gratuit |
| **URL stable** | ❌ | ✅ | ✅ |
| **Mobile bookmarkable** | ❌ | ✅ | ✅ |
| **Authentification** | ❌ | ❌ | ✅ Google + MFA |
| **Public/visible** | URL aléatoire | Découvrable | Privé total |
| **Usage** | Test 5 min | Risqué | **Production perso** |

**Recommandation** :
- **Test ponctuel** : Quick
- **Usage personnel** : Named + Access (acceptable de payer 10$/an pour la sécu)
- **Tu veux gratuit total** : Named avec `.duckdns.org` + Access (mais setup DNS galère)

---

## 🛑 Comment tout arrêter

```powershell
# Si lance via .\scripts\start-tunnel.ps1 → Ctrl+C
# Si tunnel installé en service Windows :
sc.exe stop cloudflared

# Verifier process restant :
Get-Process cloudflared -ErrorAction SilentlyContinue
```

## 🐛 Troubleshooting

| Problème | Solution |
|---|---|
| `tunnel login` échoue | Vérifier qu'aucun proxy/VPN bloque dash.cloudflare.com |
| URL affiche 502 Bad Gateway | Le service local (3000 ou 8000) n'est pas lancé |
| Cloudflare Access redirige en boucle | Cookies bloqués / domaine wildcard mal configuré |
| Latence élevée | Cloudflare edge le plus proche peut être loin — choisir région dans CF dashboard |
