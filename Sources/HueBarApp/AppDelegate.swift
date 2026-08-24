import AppKit
import SwiftUI
import HueKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let hotKeys = HotKeyCenter()
    private var state: HueState!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            state = HueState(client: HueClient(config: try HueConfig.load()))
        } catch {
            state = HueState(
                client: nil,
                errorMessage: "Credentials introuvables (~/.config/hue/credentials.env)"
            )
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PanelView(state: state))

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "HueBar")
            button.target = self
            button.action = #selector(togglePopover)
        }

        HotKeyCenter.action = { [weak self] in self?.togglePopover() }
        hotKeys.register()

        registerLoginItemOnFirstLaunch()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            Task { await state.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    /// « Ouvrir au login » actif par défaut, mais on respecte un choix utilisateur ultérieur.
    private func registerLoginItemOnFirstLaunch() {
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        LoginItem.set(true)
        UserDefaults.standard.set(true, forKey: key)
    }
}
