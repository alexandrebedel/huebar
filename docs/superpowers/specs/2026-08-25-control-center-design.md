# HueBar — Bouton Control Center (sous-projet A)

**Date** : 2026-08-25
**Statut** : approuvé (design validé en conversation)

## Objectif

Un contrôle tiers dans le Control Center de macOS 26 : un bouton « HueBar » (icône ampoule) qui ouvre le panneau HueBar. L'utilisateur l'ajoute via « Modifier les contrôles » du Control Center.

## Décisions validées

- **Un seul contrôle** : ouvrir le panneau (pas de toggles de pièces ni de scènes dans le Control Center — choix utilisateur).
- Le panneau menu bar existant reste inchangé.

## Architecture

- **Widget extension** `HueBarControls.appex` embarquée dans `HueBar.app` :
  - `ControlWidget` + `ControlWidgetButton` (WidgetKit, macOS 26)
  - Le bouton exécute un `AppIntent` qui ouvre le deep link `huebar://panel`
- **App** : enregistre le scheme `huebar://` (CFBundleURLTypes) ; `AppDelegate` gère l'URL et ouvre le popover (réutilise `togglePopover`).
- **Build** : le repo passe de « SwiftPM pur » à « SwiftPM (HueKit, tests) + projet Xcode généré par xcodegen (app + extension) ». `make install` enchaîne : `swift test` (HueKit) → `xcodegen` → `xcodebuild` (signature locale ad hoc) → copie `/Applications` → relance. Aucune ouverture d'Xcode requise.
- Détails d'API exacts (plist de l'extension, sandbox, enregistrement dans la galerie) : consignés dans le plan d'implémentation, informés par la recherche technique.

## Critères d'acceptation

1. `make install` produit et lance HueBar.app avec l'extension embarquée.
2. Le contrôle « HueBar » apparaît dans la galerie du Control Center (après un premier lancement de l'app).
3. Un clic sur le contrôle ouvre le panneau HueBar.
4. Le comportement existant (menu bar, ⌥H, login item) est inchangé ; les 34 tests HueKit passent.

## Hors périmètre

Toggles de pièces/scènes dans le Control Center (extension future possible).
