# Google APIs à activer (toutes)

Marc veut accès à **tous les services Google** depuis le hub. Voici la liste complète des APIs à activer dans Google Cloud Console, avec leur usage et les scopes OAuth nécessaires.

> Toutes ces APIs partagent le même **OAuth 2.0 Client** déjà créé (Client ID `327399868142-...`). Pas besoin de recréer un client par service.

## Liens directs d'activation

| Service | API | Lien activation | Scope OAuth (read-only) |
|---|---|---|---|
| 🗺️ Maps | Maps JavaScript API | ✅ déjà activée | (clé API, pas OAuth) |
| 📸 Photos | [Photos Library API](https://console.cloud.google.com/apis/library/photoslibrary.googleapis.com) | clic | `photoslibrary.readonly` |
| 📧 Gmail | [Gmail API](https://console.cloud.google.com/apis/library/gmail.googleapis.com) | clic | `gmail.readonly` |
| 📅 Calendar | [Calendar API](https://console.cloud.google.com/apis/library/calendar-json.googleapis.com) | clic | `calendar.readonly` |
| 📁 Drive | [Drive API](https://console.cloud.google.com/apis/library/drive.googleapis.com) | clic | `drive.readonly` |
| 💪 Fit | [Fitness API](https://console.cloud.google.com/apis/library/fitness.googleapis.com) | clic | `fitness.activity.read`, `fitness.body.read`, `fitness.sleep.read` |
| 👥 People | [People API](https://console.cloud.google.com/apis/library/people.googleapis.com) | clic | `contacts.readonly` |
| ✅ Tasks | [Tasks API](https://console.cloud.google.com/apis/library/tasks.googleapis.com) | clic | `tasks.readonly` |
| 📺 YouTube | [YouTube Data API v3](https://console.cloud.google.com/apis/library/youtube.googleapis.com) | clic | `youtube.readonly` |
| 🌐 Chrome | [Safe Browsing API](https://console.cloud.google.com/apis/library/safebrowsing.googleapis.com) | clic | (pas user data) |

## Scopes complets pour OAuth consent

Pour que le hub demande **un seul consent screen** avec tous les services :

```
openid
email
profile
https://www.googleapis.com/auth/photoslibrary.readonly
https://www.googleapis.com/auth/gmail.readonly
https://www.googleapis.com/auth/calendar.readonly
https://www.googleapis.com/auth/drive.readonly
https://www.googleapis.com/auth/fitness.activity.read
https://www.googleapis.com/auth/fitness.body.read
https://www.googleapis.com/auth/fitness.sleep.read
https://www.googleapis.com/auth/fitness.location.read
https://www.googleapis.com/auth/contacts.readonly
https://www.googleapis.com/auth/tasks.readonly
https://www.googleapis.com/auth/youtube.readonly
```

⚠️ Plus de 10 scopes "sensibles" → Google peut demander une **vérification du consent screen** (audit). Pour usage perso (test users uniquement), pas de problème. Pour publication large, il faudrait justifier chaque scope.

## Configuration consent screen

1. Aller à [APIs & Services → OAuth consent screen](https://console.cloud.google.com/apis/credentials/consent)
2. **User type** : External (sauf si tu as Google Workspace pro)
3. **App name** : `Hub perso de Marc`
4. **User support email** : `marc.richard4@gmail.com`
5. **Developer contact** : `marc.richard4@gmail.com`
6. **Authorized domains** : `localhost` (pour dev) — plus tard ajouter ton domaine Cloudflare Tunnel

7. **Scopes** : ajouter les scopes ci-dessus (un par un)
8. **Test users** : ajouter `marc.richard4@gmail.com` (sinon refus du flow)

9. **Publishing status** : laisser "Testing" — limite à 100 users (largement assez pour usage perso). Pas besoin de publier.

## Services Google sans API publique

Ces services existent mais n'ont pas d'API officielle utilisable directement :

| Service | Solution |
|---|---|
| Google Keep (notes) | Bibliothèque non officielle [keepapi](https://github.com/kiwiz/gkeepapi) — fragile, peut casser |
| Google Photos historique | Photos Library API ne donne accès qu'aux albums créés via app — pour TOUT l'historique : Google Takeout (export ZIP manuel) |
| Google Maps Timeline | Idem : Takeout uniquement (`Records.json`) |
| Chrome history / bookmarks | API native Chrome Extension uniquement (pas REST) |
| Google Search history | Pas d'API publique |

Pour ces services → **Google Takeout** (https://takeout.google.com) → ZIP → ingest dans hub-ingest.

## Ordre recommandé d'activation

Pour démarrer rapidement, active dans cet ordre :

1. **OAuth consent screen** (obligatoire — bloque tout sinon)
2. **Maps JavaScript API** (déjà ✅)
3. **Drive API** (le plus simple à tester — liste tes fichiers)
4. **Gmail API** (Phase 3)
5. **Photos Library API** (Phase 3)
6. **Calendar API** (Phase 5)
7. **Fitness API** (Phase 5)
8. **People + Tasks + YouTube** (au fur et à mesure)

## APIs non-Google complémentaires (futures)

Ces services ont leur propre OAuth (pas Google). Setup séparé :

| Service | Lien |
|---|---|
| Strava (sport) | https://www.strava.com/settings/api |
| Spotify (musique) | https://developer.spotify.com/dashboard |
| GitHub (code) | https://github.com/settings/developers |
| HIBP (security breach check) | https://haveibeenpwned.com/API/Key |
| OpenWeather (météo) | https://openweathermap.org/api |

Tous gratuits pour usage perso. À setup quand on attaque les phases concernées.
