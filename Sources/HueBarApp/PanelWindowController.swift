import AppKit
import SwiftUI

/// Fenêtre du panneau : centrée sur l'écran actif, sans barre de titre visible.
/// Échap, ⌘W ou un clic dans une autre app la masquent — mais pas les boîtes de
/// permissions système, qui volent le focus sans que l'utilisateur soit « parti ».
@MainActor
final class PanelWindowController {
    static let defaultSize = NSSize(width: 900, height: 620)

    private let window: PanelWindow
    private var activationObserver: NSObjectProtocol?
    var onShow: (() -> Void)?

    init(rootView: some View) {
        window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Flottante : un panneau de contrôle ne doit pas disparaître derrière l'app
        // active (les popups TCC volent le focus et la renvoyaient à l'arrière-plan).
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        // Le bouton rouge reste visible (fermer la fenêtre = la masquer) ;
        // réduire/agrandir n'ont pas de sens pour ce panneau.
        for button: NSWindow.ButtonType in [.miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentViewController = NSHostingController(rootView: rootView)

        // Clic hors de l'app = masquer, déclenché par l'ACTIVATION d'une vraie app
        // (`.regular`). Les popups de permissions (TCC, SecurityAgent…) volent le focus
        // sans jamais activer d'app régulière — et pendant qu'ils sont affichés,
        // `frontmostApplication` rapporte l'app régulière d'arrière-plan : interroger
        // le premier plan à la désactivation masquait donc la fenêtre pendant
        // l'approbation (constaté en réel). Seul l'événement d'activation est fiable.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                self?.hideIfUserSwitched(to: app)
            }
        }
    }

    /// Masque seulement si l'utilisateur est vraiment parti : une autre app `.regular`
    /// vient d'être activée (les agents système sont `.accessory`/`.prohibited`).
    private func hideIfUserSwitched(to app: NSRunningApplication?) {
        guard let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular,
              window.isVisible, !NSApp.isActive
        else { return }
        hide()
    }

    func show() {
        if let screen = NSScreen.main {
            window.setFrame(
                PanelGeometry.frame(size: Self.defaultSize, screenVisibleFrame: screen.visibleFrame),
                display: true
            )
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        onShow?()
    }

    func hide() { window.orderOut(nil) }

    /// Masque si la fenêtre a le focus, sinon l'amène au premier plan : une fenêtre
    /// visible mais enterrée derrière d'autres apps doit revenir devant, pas disparaître.
    func toggle() {
        if window.isKeyWindow {
            hide()
        } else {
            show()
        }
    }
}

/// `.titled` pour les coins arrondis natifs et le focus clavier ; le titre est caché.
private final class PanelWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "w" {
            orderOut(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum PanelGeometry {
    /// Part de l'écran visible que la fenêtre peut occuper au maximum.
    static let maxHeightFraction = 0.8
    static let maxWidthFraction = 0.9
    /// Position verticale du bas de la fenêtre dans l'espace restant :
    /// 0.5 = centre exact, plus haut = fenêtre légèrement au-dessus du milieu.
    static let verticalBias = 0.55

    /// Centrée horizontalement, légèrement au-dessus du centre vertical.
    static func frame(size: NSSize, screenVisibleFrame screen: NSRect) -> NSRect {
        let height = min(size.height, screen.height * maxHeightFraction)
        let width = min(size.width, screen.width * maxWidthFraction)
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.minY + (screen.height - height) * verticalBias,
            width: width,
            height: height
        )
    }
}
