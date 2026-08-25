# HueBar 💡

App menu bar macOS pour piloter des Philips Hue **en local** (API CLIP v2 du bridge, zéro cloud) — avec sync musique → lumières et enregistreur de mixes.

## Fonctions

- Toggle et luminosité par pièce, « Tout éteindre / allumer », scènes en un clic
- Contrôle par lampe : on/off, luminosité, couleur
- **Contrôle Control Center** (macOS 26) : bouton qui ouvre le panneau
- **🎵 Sync musique → lumières** : streaming Hue Entertainment (DTLS, ~50 Hz) piloté par l'analyse temps réel (FFT + détection de beat) de l'audio du Mac ou d'une entrée audio (ex. table de mixage USB, avec choix de la paire de canaux) — modes Club et Chill
- **● REC** : enregistre l'entrée sélectionnée en WAV 24-bit (sample rate natif) dans `~/Music/PX5/`
- Hotkey global ⌥H, lancement au login, aucune icône Dock

## Prérequis

`~/.config/hue/credentials.env` :

    export HUE_BRIDGE=<ip-du-bridge>
    export HUE_KEY=<clé-api>
    export HUE_CLIENTKEY=<clientkey-du-pairing>   # requis pour la sync musique

(Clés créées en appuyant sur le bouton du bridge puis `POST /api` avec
`{"devicetype":"huebar","generateclientkey":true}` — la réponse contient `username` et `clientkey`.)

La sync utilise la zone Entertainment nommée « HueBar Sync » (ou la première zone du bridge).

## Permissions macOS

Demandées à la première utilisation : Réseau local (pilotage du bridge), Enregistrement
audio système (source « Audio du Mac »), Microphone (entrées USB). Signature ad hoc :
la permission audio système peut être redemandée après un rebuild.

## Build

    make test     # tests unitaires SwiftPM (HueKit, WaveKit, SyncKit)
    make app      # xcodegen + xcodebuild (app + extension Control Center)
    make install  # installe dans /Applications, enregistre l'extension, lance

Tests d'intégration sur le vrai bridge (fait clignoter une lampe) :

    HUE_INTEGRATION=1 swift test --filter IntegrationTests

Swift 6.3+ / macOS 26+. Dépendances : aucune (xcodegen requis pour le build).

## Architecture

- `HueKit` (SwiftPM) : config, modèles CLIP v2, client HTTPS local, encodeur HueStream v2, transport DTLS-PSK
- `WaveKit` : sources audio (tap système CoreAudio, entrées AVAudioEngine), analyse FFT/beat, enregistreur WAV
- `SyncKit` : mapping audio → couleurs (Club/Chill), moteur d'orchestration 50 Hz
- `Sources/HueBarApp` : app AppKit/SwiftUI (status item + popover) ; `Sources/HueBarControls` : extension WidgetKit
