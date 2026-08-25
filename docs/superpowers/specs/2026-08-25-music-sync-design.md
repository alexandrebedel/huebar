# HueBar — Sync musique → lumières (sous-projet B)

**Date** : 2026-08-25
**Statut** : approuvé (design validé en conversation)

## Objectif

Les Philips Hue réagissent en temps réel à la musique : section « 🎵 Musique » dans le panneau HueBar avec choix de la source audio, deux styles (Club / Chill), start/stop. Streaming via l'API Hue Entertainment (DTLS, ~50 Hz) — pas les commandes REST classiques.

## Contexte bridge (déjà en place)

- Zone Entertainment **« HueBar Sync »** créée par API : `bce767fc-ddba-4747-bec1-2313f5dfbbac`, type `music`, 6 lampes (5 Séjour à l'avant y=1, Essential lamp 3 Cuisine à l'arrière y=-1). Positions affinables dans l'app Hue — l'app lit les channels dynamiquement, jamais d'IDs en dur.
- Credentials : `~/.config/hue/credentials.env` contient désormais `HUE_CLIENTKEY` (PSK du pairing) en plus de `HUE_BRIDGE`/`HUE_KEY`.

## Sources audio (validé avec l'utilisateur)

1. **« Audio du Mac »** : tout l'audio système (Spotify, SoundCloud, YouTube…) via Core Audio process tap (macOS 14.4+). Permission « Enregistrement audio système » demandée au premier usage.
2. **Périphérique d'entrée** : n'importe quel device d'entrée CoreAudio. Cas d'usage clé : la **Xone:PX5 en USB**, interface multi-canaux — l'utilisateur doit pouvoir choisir **le device ET la paire de canaux** (ex. la paire qui porte le master). Noms de canaux affichés si le device les fournit. Le choix est mémorisé.
   - Note : la PX5 en Bluetooth est sortie seulement — inutilisable comme source ; l'USB est requis. Les canaux exacts de la PX5 seront relevés quand elle sera branchée en USB (détection dynamique de toute façon).

## Chaîne de traitement

```
Source (tap système | device input) → Analyse (FFT, bandes, beat) → Mapping (Club|Chill) → EntertainmentStreamer (DTLS 50 Hz)
```

- **Analyse** : FFT (Accelerate/vDSP), fenêtre ~1024, ~50-60 analyses/s ; énergie basses/mids/aigus, RMS global, détection de beat par flux d'énergie basses avec seuil adaptatif, lissages.
- **Mode Club** : flashs de luminosité calés sur les kicks, rotation/changements de teinte vifs, couleurs par bande de fréquence, decay rapide.
- **Mode Chill** : teintes qui dérivent lentement (spectre → position dans une palette), luminosité suivant le RMS lissé, transitions douces.
- **Streaming** : REST start → handshake DTLS-PSK (clientkey) UDP 2100 → messages HueStream v2 par channel de la zone à ~50 Hz → stop propre. Reconnexion/erreurs remontées dans l'UI.

## UI (section Musique du panneau)

- Picker source : « Audio du Mac » + devices d'entrée détectés (+ picker paire de canaux si device multi-canal, avec noms)
- Boutons mode : Club / Chill (switchables à chaud)
- Start/Stop + indicateur de niveau simple + état d'erreur lisible
- Pendant la sync, les contrôles manuels de lampes du panneau restent affichés mais la zone streamée est pilotée par la musique (comportement Hue standard : le streaming a priorité)

## Gestion d'erreurs

- Permission audio refusée → message clair avec le chemin Réglages
- Bridge/DTLS : échec de handshake ou coupure → arrêt propre + bandeau erreur + retry
- Device débranché en cours → stop propre + message

## Tests

- Analyse (bandes, beat, lissage) et mapping des modes : tests unitaires purs (buffers synthétiques : sinus basse + clics)
- Encodage des messages HueStream v2 : tests unitaires octet par octet
- REST start/stop : tests avec MockURLProtocol
- DTLS + audio réels : smoke test sur machine (gated `HUE_INTEGRATION`)

## Hors périmètre

Positions spatiales avancées (l'app traite les channels de façon uniforme ou par simple position x fournie par la zone), multi-zones, sync sur l'app Hue mobile.
