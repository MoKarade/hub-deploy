# Vault de secrets perso (chiffré, sur Google Drive)

Tous tes secrets (clés API, OAuth client, mots de passe, tokens) sont dans un fichier **unique chiffré** : `hub-secrets-vault.age` à la racine du projet sur Drive.

Le chiffrement utilise **age** (dérivé de NaCl, très simple, format texte). Le fichier `.age` peut être uploadé sur Drive sans risque — seul ton PC peut le déchiffrer avec la clé privée locale.

---

## 🔑 Architecture

```
G:\Mon disque\...\hub-secrets-vault.age   ← chiffré (Drive sync OK)
                                             contient: Maps key, OAuth client, postgres pwd, etc.
                                             ↑
                                             | chiffré avec ta clé publique
                                             ↓
C:\Users\dessin14\.hub-secrets\
   ├── age-key.txt              ← clé PRIVÉE (jamais sur Drive, jamais Git)
   └── age-public-key.txt       ← clé publique (peut être partagée)
```

## 🔓 Déchiffrer le vault

```powershell
cd "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-deploy"
.\scripts\decrypt-vault.ps1
```

Le contenu s'affiche dans le terminal (pas de fichier déchiffré laissé sur disque). Copie ce dont tu as besoin.

## ✏️ Modifier le vault

```powershell
# 1. Décrypter dans un fichier temporaire
$ageExe = "C:\Users\dessin14\AppData\Local\Microsoft\WinGet\Packages\FiloSottile.age_Microsoft.Winget.Source_8wekyb3d8bbwe\age\age.exe"
$keyFile = "C:\Users\dessin14\.hub-secrets\age-key.txt"
$vault = "G:\Mon disque\PERSO & LOISIRS\AUTOMATISATION\Projets\Hub perso\hub-secrets-vault.age"
$temp = "C:\Users\dessin14\.hub-secrets\edit-temp.yaml"

& $ageExe -d -i $keyFile -o $temp $vault

# 2. Ouvrir dans VS Code / Notepad
code $temp   # ou notepad $temp

# 3. Sauvegarder, puis re-chiffrer
$pubKey = (Get-Content "C:\Users\dessin14\.hub-secrets\age-public-key.txt").Trim()
& $ageExe -e -r $pubKey -o $vault $temp

# 4. Supprimer le temp
Remove-Item $temp
```

## ⚠️ Backup de la clé privée

**TRÈS IMPORTANT** : si tu perds `C:\Users\dessin14\.hub-secrets\age-key.txt`, tu ne peux plus déchiffrer le vault. Backup obligatoire :

| Méthode | Recommandation |
|---|---|
| **USB drive** | Copie `age-key.txt` sur une clé USB que tu gardes en sécurité |
| **Password manager** | Colle le contenu de `age-key.txt` dans une note 1Password / Bitwarden / KeePass |
| **Imprimé papier** | Imprime le fichier (16 lignes texte) et garde en lieu sûr |

Ne JAMAIS uploader la clé privée sur Drive, GitHub, ou un autre service cloud.

## 🔄 Quoi faire si la clé fuit / est compromise

1. Générer une nouvelle paire age (`age-keygen -o new-key.txt`)
2. Décrypter le vault avec l'ANCIENNE clé
3. Re-chiffrer avec la NOUVELLE clé publique
4. Régénérer / révoquer toutes les clés API et OAuth secrets dans leurs consoles respectives (Google Cloud, Cloudflare, etc.)
5. Mettre à jour les valeurs dans le vault, re-chiffrer
6. Mettre à jour les `.env` files locaux

## 📋 Contenu actuel du vault

(Voir le contenu réel via `decrypt-vault.ps1`. Aperçu structure :)

```yaml
google:
  maps_api_key: AIzaSy...
  oauth:
    client_id: ...
    client_secret: GOCSPX-...
    test_users: [marc.richard4@gmail.com]
hub_core:
  postgres: { user, password, db }
  secret_key: ...
cloudflare: { tunnel_token, account_id, zone_id }
duckdns: { token, domain }
strava: { client_id, client_secret }
garmin: { email, password_dpapi }
```

## 🚫 NE PAS commiter

- `*.age` (le vault chiffré) — voir `.gitignore`
- `.hub-secrets/` (clés age locales) — hors du projet, sur `C:\Users\<user>\`
- Aucune valeur en clair dans le code, jamais.
