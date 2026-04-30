# Installer le Hub comme une vraie app

Le Hub perso peut s'installer comme une **vraie application** sur ton PC et ton téléphone, sans passer par un App Store. Plusieurs options selon tes besoins.

---

## 🖥️ Option A — App Desktop Windows (recommandée)

**Une vraie app dans le menu Démarrer + raccourci bureau, qui démarre tout automatiquement et ouvre une fenêtre standalone (sans barre d'URL).**

### Installation (1 fois)

```powershell
cd "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-deploy"
.\scripts\install-desktop-app.ps1
```

Ce script crée :
- ✅ Raccourci `Hub perso.lnk` sur le bureau
- ✅ Entrée dans le menu Démarrer (cherche "Hub perso")
- ✅ Icône custom (vert avec H)

### Utilisation

**Double-clique sur le raccourci** → l'app :
1. Démarre Ollama (daemon LLM)
2. Démarre la stack Docker (postgres + hub-core) si Docker installé
3. Démarre le frontend Next.js sur :3000
4. Ouvre Chrome en **mode app standalone** (vraie fenêtre, sans barre d'URL)

Tu fermes la fenêtre comme une app normale. Pour arrêter le hub-core en arrière-plan : `.\scripts\stop_hub.ps1`

---

## 📱 Option B — PWA Mobile (Android/iOS)

**Le Hub s'installe comme une app sur ton téléphone via "Add to Home Screen" — pas besoin d'App Store.**

### Prérequis

- Le hub doit être accessible depuis ton téléphone, donc soit :
  - **Réseau local** : ton téléphone connecté au même Wi-Fi que ton PC, et tu accèdes via `http://<IP-DU-PC>:3000`
  - **Tunnel Cloudflare** (Phase 0 fin) : `https://hub.tonsousdomaine.com` accessible de partout

### Sur Android (Chrome/Edge/Brave)

1. Ouvre `https://ton-hub-url` dans le navigateur
2. Tape sur le menu `⋮` (3 points)
3. Choisis **"Installer l'application"** ou **"Ajouter à l'écran d'accueil"**
4. Confirme — l'icône apparaît sur ton écran d'accueil
5. Tape sur l'icône → l'app s'ouvre en plein écran (sans barre Chrome)

### Sur iOS/iPadOS (Safari)

1. Ouvre `https://ton-hub-url` dans **Safari** (obligatoire, pas Chrome iOS)
2. Tape sur le bouton de partage `⎙`
3. Fais défiler et choisis **"Sur l'écran d'accueil"**
4. Confirme — l'icône apparaît
5. Tape dessus → app fullscreen

### Sur Desktop (Chrome/Edge/Brave)

Même principe :
1. Ouvre `http://localhost:3000`
2. Cherche l'icône **"Installer"** dans la barre d'URL (à droite, ressemble à un petit écran avec une flèche)
3. Click → "Installer Hub perso"
4. L'app apparaît dans le menu Démarrer + un raccourci dédié

> Note : Sur ce hub, une bannière "Installer Hub perso" apparaît automatiquement en bas-droite quand le navigateur détecte que l'app est installable.

---

## 🛠️ Option C — App Tauri Native (avancé, plus tard)

**Une vraie app .exe standalone (10 MB) avec WebView native, plus rapide qu'une PWA.**

À considérer si tu veux :
- Distribuer une release `.exe` que tu peux installer sur d'autres PC
- Une fenêtre 100% native sans dépendre de Chrome
- Auto-update intégré

Setup :
```bash
cd hub-frontend
npm install -D @tauri-apps/cli
npx tauri init
npx tauri build
# → release/bundle/msi/hub-perso.msi
```

⚠️ Nécessite l'installation de Rust (~700 MB toolchain). Pas urgent — les options A et B suffisent largement pour un usage perso.

---

## 📊 Comparaison

| | Option A (Chrome --app) | Option B (PWA install) | Option C (Tauri) |
|---|---|---|---|
| **Setup** | 1 script PowerShell | 1 click dans le navigateur | Install Rust + bundle |
| **Bundle size** | 0 (réutilise Chrome) | 0 (réutilise Chrome) | ~10 MB |
| **Offline** | Non (besoin du backend) | Partiel (cache statique) | Non (besoin du backend) |
| **Mobile** | ❌ | ✅ Android + iOS | ❌ |
| **Démarre tout auto** | ✅ (Ollama + Docker + frontend) | ❌ (besoin du hub déjà up) | ❌ |
| **Auto-update** | ✅ (juste git pull) | ✅ (juste F5) | Manuel |

**Recommandation** :
- **Sur le PC où tourne le hub** → **Option A** (lance tout d'un click)
- **Sur ton téléphone** → **Option B** (PWA install)
- **Plus tard si tu veux distribuer** → **Option C**

---

## 🐛 Troubleshooting

### "L'icône n'apparaît pas après install-desktop-app.ps1"

Refresh l'explorateur : appuie sur `F5` sur le bureau, ou redémarre l'explorateur Windows (`taskkill /f /im explorer.exe; start explorer.exe`).

### "Le bouton 'Installer' n'apparaît pas dans Chrome"

Trois conditions doivent être remplies :
1. Le site doit être servi en HTTPS (sauf `localhost` qui est exempté)
2. Un `manifest.json` valide doit être présent (✅ déjà en place)
3. Au moins un `icon` 192x192+ doit exister dans le manifest (✅ icon.svg)

Si rien ne marche, force-refresh : `Ctrl+Shift+R`.

### "Sur iOS, l'app ne s'installe pas"

Sur iPhone/iPad, **utilise Safari, pas Chrome**. Apple ne permet pas aux autres navigateurs d'installer des PWA (limitation iOS).

### "La PWA mobile montre 'Failed to fetch'"

Le frontend tourne sur le PC, pas sur le téléphone. Tu dois soit :
- Connecter ton téléphone au même Wi-Fi et utiliser `http://<IP-PC>:3000`
- Ou setup le tunnel Cloudflare (Phase 0 fin du master plan)
