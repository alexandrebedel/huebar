# HueBar — Design

**Date** : 2026-08-24
**Statut** : approuvé (design validé en conversation)

## Objectif

App menu bar macOS native pour piloter les Philips Hue d'Alex **en local** via l'API CLIP v2 du bridge (192.168.1.134, bridge v2 BSB002). Pas de cloud, latence quasi nulle, pas d'icône Dock.

## Environnement cible

- macOS 26 (Tahoe), Apple Silicon, Xcode 26.6 / Swift 6.3 disponible
- Bridge : `192.168.1.134`, API key dans `~/.config/hue/credentials.env` (variables `HUE_BRIDGE` et `HUE_KEY`)
- Installation : `~/repositories/huebar`, build sans ouvrir Xcode (`make install` → `/Applications/HueBar.app`)

## Inventaire actuel (référence)

- **Pièces** : Séjour (`06986d21-…`), Cuisine (`af54d344-…`), groupe « toute la maison » = `bridge_home` (`1a068e3a-…`)
- **6 lampes** : Hue go 1 & 2, Hue lightstrip 1, Hue Essential lamp 1-3 (toutes couleur)
- **20 scènes** réparties Séjour / Cuisine / maison entière
- L'app ne code jamais ces IDs en dur : tout est découvert via l'API à l'exécution.

## UX du panneau

Icône ampoule (SF Symbol) dans la menu bar. Clic ou raccourci global **⌥H** → popover :

1. **En haut** : bouton « Tout éteindre / Tout allumer » (grouped_light du `bridge_home`)
2. **Par pièce** (Séjour, Cuisine) :
   - toggle on/off (grouped_light de la pièce) + slider de luminosité pièce
   - grille de **scènes** de la pièce en pastilles cliquables
   - disclosure « Lampes » → par lampe : toggle, slider, pastille couleur ouvrant un color picker
3. **En bas** : engrenage → « Ouvrir au login » (activé par défaut, via `SMAppService`), « Quitter »

Comportement : état rafraîchi à l'ouverture du panneau et après chaque commande. Optimistic UI (le toggle bascule immédiatement, rollback si l'appel échoue).

## Architecture

Trois modules :

### 1. `HueClient` (réseau)

- HTTPS vers `https://<bridge>/clip/v2/...`, header `hue-application-key`
- Certificat auto-signé du bridge accepté **uniquement** pour l'IP/bridge configuré (delegate URLSession dédié)
- Endpoints : GET `resource/light`, `resource/room`, `resource/scene`, `resource/grouped_light` ; PUT `resource/light/{id}`, `resource/grouped_light/{id}` (on, dimming, color xy) ; PUT `resource/scene/{id}` (recall active)
- Timeouts courts (2 s), erreurs typées

### 2. `HueState` (état + actions)

- `@Observable` store : pièces, lampes par pièce, scènes par pièce, états on/dim
- Actions : toggleRoom, setRoomBrightness, recallScene, toggleLight, setLightBrightness, setLightColor (RGB → xy CIE)
- Charge la config depuis `~/.config/hue/credentials.env` ; si absent → état d'erreur explicite

### 3. UI (AppKit + SwiftUI)

- `NSStatusItem` + `NSPopover` contenant un `NSHostingController` (pattern choisi plutôt que `MenuBarExtra` pour permettre le toggle programmatique par hotkey)
- Hotkey global ⌥H via `RegisterEventHotKey` (Carbon, zéro dépendance)
- `LSUIElement = true` (pas de Dock)

## Gestion d'erreurs

- Bridge injoignable → bandeau « Bridge injoignable » + bouton réessayer dans le panneau
- Credentials manquants → message explicite avec le chemin attendu
- Échec d'une commande → rollback de l'optimistic UI

## Tests

- **TDD** sur `HueClient` (décodage réponses, encodage requêtes, via `URLProtocol` mocké) et sur la logique de `HueState` (mapping pièces/lampes/scènes, conversion RGB→xy)
- UI : vérification manuelle en conditions réelles (les lampes du salon font foi)

## Build & livraison

- Swift Package (executable) + script d'assemblage du bundle : `make app` → `build/HueBar.app` (binaire + Info.plist + icône), codesign ad hoc ; `make install` → copie dans `/Applications` et lance
- Repo git `~/repositories/huebar`, README

## Hors périmètre v1

- Bouton Control Center (ControlWidget) — extension future
- Mises à jour temps réel via `/eventstream` (SSE)
- Onboarding de pairing pour un bridge inconnu
