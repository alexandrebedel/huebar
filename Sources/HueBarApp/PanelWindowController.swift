import AppKit
import SwiftUI

/// Fenêtre du panneau : centrée sur l'écran actif, sans barre de titre visible,
/// persistante (elle reste ouverte si elle perd le focus). Échap ou ⌘W la masquent.
@MainActor
final class PanelWindowController {
    static let defaultSize = NSSize(width: 900, height: 620)

    private let window: PanelWindow
    var onShow: (() -> Void)?

    init(rootView: some View) {
        window = PanelWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentViewController = NSHostingController(rootView: rootView)
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
    /// Centrée horizontalement, centre vertical légèrement au-dessus du milieu,
    /// clampée à 80 % de la hauteur (et 90 % de la largeur) visibles de l'écran.
    static func frame(size: NSSize, screenVisibleFrame screen: NSRect) -> NSRect {
        let height = min(size.height, screen.height * 0.8)
        let width = min(size.width, screen.width * 0.9)
        return NSRect(
            x: screen.midX - width / 2,
            y: screen.minY + (screen.height - height) * 0.55,
            width: width,
            height: height
        )
    }
}
