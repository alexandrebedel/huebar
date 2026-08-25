# HueBar — Fenêtre app (v2 du panneau) + fix Control Center

**Date** : 2026-08-25
**Statut** : approuvé (design validé en conversation)

## Objectif

Transformer le popover en une vraie fenêtre d'app : centrée à l'écran, plus grande, avec une mise en page sidebar + grille de scènes illustrées. Corriger au passage le clic du contrôle Control Center qui ne fait rien.

## Bug Control Center — cause racine (investigation du 25/08)

- `OpenPanelIntent` déclare `supportedModes: .foreground` : le système exécute ce type d'intent **dans l'app**, pas dans l'extension.
- Or l'intent n'est compilé que dans l'appex : l'app n'a aucun `Metadata.appintents`. Au clic, LaunchServices résout l'app comme cible, ne trouve pas l'intent, abandonne en silence (aucune erreur loggée).
- Le deep link `huebar://panel` fonctionne, lui (vérifié par `open` : l'app passe Visible/UserInteractiveFocal).

**Fix (fallback §A3.2 du plan control-center)** : source `OpenPanelIntent` partagée, compilée dans **les deux cibles** (app + appex). Le `perform()` s'exécute in-app et ouvre la fenêtre directement. Suppression du détour `OpenURLIntent`. Le deep link reste pour le scripting (Raycast quicklink).

## Décisions validées

- **Fenêtre centrée partout** : icône menu bar, ⌥H, contrôle CC et deep link ouvrent tous la même fenêtre centrée (plus d'ancrage sous l'icône).
- **Persistante** : elle reste ouverte si elle perd le focus. Fermeture : Échap, ⌘W, ou re-toggle (icône / ⌥H / CC).
- **Menu bar only** : pas d'icône Dock ni ⌘Tab (LSUIElement conservé). Ouvrable via Raycast : « Open Application HueBar » (réouverture → fenêtre) et quicklink `huebar://panel`.
- **Layout sidebar + grille** (~900×620 pt, paysage) :
  - Sidebar gauche : pièces dans l'**ordre du bridge** (règle existante), + entrée « Musique & REC » en bas.
  - Zone principale : grille de cartes de scènes de la pièce sélectionnée (clic = appliquer), puis lampes de la pièce (rows existantes : on/off, luminosité, couleur).
  - Vue « Musique & REC » : contenu actuel de MusicSectionView + REC.
- **Cartes de scènes en dégradés générés** : les images officielles ne sont pas servies par l'API (`public_image` → 404, vérifié sur le bridge) ; chaque carte affiche un dégradé construit depuis les couleurs réelles des actions de la scène (xy → sRGB, mirek → RGB, modulé par la luminosité).
- **Nettoyage du code mort** (demande explicite) : suppression du NSPopover et de tout chemin devenu inutile après migration (OpenURLIntent, ancrage popover…).

## Architecture

- `PanelWindowController` (app) : NSWindow sans barre de titre visible, coins arrondis, ombre, niveau normal, centrée sur l'écran actif (léger décalage au-dessus du centre). `NSApp.activate` à l'ouverture ; Échap/⌘W gérés sans menu Dock.
- Calcul du frame (taille + centrage, clamp à 80 % de l'écran) : fonction pure testable.
- `SceneGradient` (HueKit, pur, sans dépendance AppKit) : `actions → stops RGB de dégradé` — fonction testable (ordre stable, fallback blanc chaud si scène sans couleur) ; l'UI convertit les RGB en `Color`.
- `OpenPanelIntent` : fichier partagé, cible app + appex ; in-app il appelle `AppDelegate.togglePanel()`.
- `applicationShouldHandleReopen` → ouvre la fenêtre (support Raycast/open -a).

## Tests

- Suite existante verte (65 tests).
- Nouveaux : frame de centrage (tailles d'écran variées), conversion mirek→RGB, génération des stops de dégradé (scène couleur, scène température, scène vide).
- Vérification manuelle utilisateur : clic CC, ⌥H, icône, Raycast, Échap/⌘W, application d'une scène depuis une carte.

## Hors scope

- SSE /eventstream, toggles de pièces dans le CC, positions spatiales, REC de l'audio système, onboarding pairing (inchangés, déjà différés).
