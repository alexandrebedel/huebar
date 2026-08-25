# Control Center Button Implementation Plan (sous-projet A)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Un contrôle « HueBar » dans le Control Center de macOS 26 qui ouvre le panneau via `huebar://panel` (déjà géré par l'app).

**Architecture:** Le build passe à xcodegen + xcodebuild (app + extension `app-extension` WidgetKit) ; HueKit reste un package SwiftPM (`swift test` inchangé). Pipeline validé de bout en bout par la recherche (macOS 26.5, Xcode 26.6, xcodegen 2.46) : enregistrement pluginkit automatique au build via lsregister.

**Faits vérifiés (recherche du 25/08) :**
- `ControlWidget`/`ControlWidgetButton` : macOS 26.0+, `@main` directement sur le ControlWidget, imports WidgetKit+SwiftUI+AppIntents.
- Extension : type `app-extension`, Info.plist `NSExtension = {NSExtensionPointIdentifier: com.apple.widgetkit-extension}` (PAS ExtensionKit), sandbox `com.apple.security.app-sandbox=true` obligatoire, bundle id préfixé par celui de l'app, deployment target 26.0, SKIP_INSTALL.
- App hôte non sandboxée + extension sandboxée : supporté (Apple DTS).
- `openAppWhenRun` déprécié → `static let supportedModes: IntentModes = .foreground`.
- Signature ad hoc `-` acceptée (build, registration) ; le clic reste à valider en réel.
- Galerie : si le contrôle n'apparaît pas, ouvrir « Modifier les widgets » du bureau force le refresh chronod (bug Tahoe connu).
- Risque identifié : OpenURLIntent + scheme custom depuis un contrôle (interdit sur iOS 18 d'après un ingénieur Apple ; macOS passe par LaunchServices, probablement OK). **Fallback prêt** : compiler l'intent dans app + extension, `supportedModes = .foreground` fait tourner `perform()` dans l'app → ouvrir le popover directement sans URL.

### Task A1 : Restructuration build (xcodegen + Makefile)

**Files:** Modify `Package.swift` (ajouter `products: [.library(name: "HueKit", targets: ["HueKit"])]`) ; Create `project.yml`, `Support/ControlsInfo.plist`, `Support/HueBarControls.entitlements` ; Modify `Makefile`, `.gitignore` (+`*.xcodeproj`, `DerivedData/`).

- [x] A1.1 `project.yml` : targets HueBar (application, sources `Sources/HueBarApp`, `INFOPLIST_FILE=Support/Info.plist` via settings — pas de bloc `info:` pour ne pas écraser notre plist, package HueKit `path: .`, embed de l'extension) + HueBarControls (`app-extension`, sources `Sources/HueBarControls`, bundle id `com.alexbedel.huebar.controls`, INFOPLIST_FILE=Support/ControlsInfo.plist, entitlements sandbox). `CODE_SIGN_IDENTITY: "-"`, `CODE_SIGN_STYLE: Manual`, deployment 26.0.
- [x] A1.2 `ControlsInfo.plist` : CFBundle basics avec `$(EXECUTABLE_NAME)`/`$(PRODUCT_BUNDLE_IDENTIFIER)` + `NSExtension`. Ajouter `NSLocalNetworkUsageDescription` au plist de l'app (préparation B, requis proprement pour le REST LAN).
- [x] A1.3 Makefile : `app` = `xcodegen generate` + `xcodebuild -project HueBar.xcodeproj -scheme HueBar -configuration Release -derivedDataPath DerivedData build` ; `install` = ditto vers /Applications + lsregister `-f -R -trusted` + open. `test` inchangé (swift test).
- [x] A1.4 Vérifier : `swift test` vert ET `make app` produit `HueBar.app` avec `Contents/PlugIns/HueBarControls.appex` signé. Commit.

### Task A2 : Le contrôle

**Files:** Create `Sources/HueBarControls/HueBarControl.swift`.

- [x] A2.1 `@main struct HueBarControl: ControlWidget` + `StaticControlConfiguration(kind: "com.alexbedel.huebar.panel")` + `ControlWidgetButton(action: OpenPanelIntent())` + `Label("HueBar", systemImage: "lightbulb.fill")` (titre simple uniquement — les sous-titres tiers sont ignorés, bug FB20022894). `OpenPanelIntent` : `supportedModes = .foreground`, `perform()` → `.result(opensIntent: OpenURLIntent(URL(string: "huebar://panel")!))`.
- [x] A2.2 `make install` ; vérifier `pluginkit -m -v -i com.alexbedel.huebar.controls` liste l'appex depuis /Applications (nettoyer les entrées parasites avec `pluginkit -r` le cas échéant). Commit.

### Task A3 : Vérification réelle

- [x] A3.1 Automatisé : pluginkit OK, app relancée, deep link `open "huebar://panel"` ouvre le panneau.
- [ ] A3.2 Utilisateur : ajouter le contrôle (Control Center → Modifier les contrôles ; si absent : clic droit bureau → Modifier les widgets, puis réessayer) et cliquer. Si le clic n'ouvre pas l'app → appliquer le fallback dual-target (intent partagé, perform in-app ouvre le popover sans URL) et réinstaller.

## Vérification finale
- [x] `make test` vert ; `make install` OK ; menu bar/⌥H/login item inchangés.
- [ ] Contrôle visible et fonctionnel dans le Control Center (validation utilisateur).
