# HueBar 💡

App menu bar macOS pour piloter des Philips Hue **en local** (API CLIP v2 du bridge, zéro cloud).

## Fonctions

- Toggle et luminosité par pièce, « Tout éteindre / allumer »
- Scènes par pièce et scènes maison en un clic
- Contrôle par lampe : on/off, luminosité, couleur
- Hotkey global ⌥H, lancement au login, aucune icône Dock

## Prérequis

`~/.config/hue/credentials.env` :

    export HUE_BRIDGE=<ip-du-bridge>
    export HUE_KEY=<clé-api>

(Clé créée en appuyant sur le bouton du bridge puis `POST /api` avec
`{"devicetype":"huebar","generateclientkey":true}`.)

## Build

    make test     # tests unitaires (HueKit)
    make app      # assemble build/HueBar.app
    make install  # installe dans /Applications et lance

Swift 6.3+ / macOS 15+. Aucune dépendance.
