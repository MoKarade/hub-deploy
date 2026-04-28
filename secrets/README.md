# Vault de secrets — age + sops

Tous les secrets sensibles (tokens API, credentials banque, clés, etc.) sont chiffrés avec [age](https://github.com/FiloSottile/age) via [sops](https://github.com/getsops/sops). Ils ne quittent JAMAIS le repo en clair.

## Setup initial (une fois)

```powershell
# 1. Génère ta clé age personnelle (à garder précieusement, 1 fois pour toute la vie)
age-keygen -o $env:USERPROFILE\.age\hub.key

# 2. Récupère la public key de la clé
age-keygen -y $env:USERPROFILE\.age\hub.key
# → âge: age1...    (note-la, on s'en sert dans .sops.yaml)

# 3. Configure sops dans le repo (.sops.yaml en racine)
# Voir hub-deploy/.sops.yaml
```

## Chiffrer un secret

```powershell
# Édition d'un fichier déjà chiffré (sops l'ouvre déchiffré dans un éditeur)
sops secrets/plaid.enc.yaml

# Création d'un nouveau secret chiffré
sops -e secrets/plaid.yaml > secrets/plaid.enc.yaml
```

## Déchiffrer en mémoire (utilisé par les scripts)

```powershell
sops -d secrets/credentials.enc.yaml
```

## Règles à respecter

- **JAMAIS** commit la clé privée `~/.age/hub.key`
- **JAMAIS** commit un fichier `.yaml` non chiffré dans `secrets/`
- Le `.gitignore` du repo bloque `secrets/*.yaml` et n'autorise que `secrets/*.enc.yaml`
- Sauvegarde la clé age dans ton coffre OneDrive (chiffré) ET sur clé USB (multi-supports)
- Si tu perds la clé age → tous les secrets sont irrécupérables

## Liste des secrets attendus

À créer au fur et à mesure des intégrations :

- `secrets/google.enc.yaml` — OAuth tokens Gmail/Photos/Calendar
- `secrets/bank.enc.yaml` — credentials de ta méthode banque (à définir, pas de Plaid sandbox)
- `secrets/cloudflare.enc.yaml` — token tunnel + Access keys
- `secrets/duckdns.enc.yaml` — token DuckDNS
- `secrets/ntfy.enc.yaml` — clé pour push notifications
