import AppKit
import SwiftUI
import HueKit
import SyncKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let hotKeys = HotKeyCenter()
    private var state: HueState!
    private var musicEngine: MusicSyncEngine?
    private let recorderController = RecorderController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let config = try HueConfig.load()
            let client = HueClient(config: config)
            state = HueState(client: client)
            musicEngine = MusicSyncEngine(config: config, entertainment: client, transport: DTLSStreamer())
        } catch {
            state = HueState(
                client: nil,
                errorMessage: "Credentials introuvables (~/.config/hue/credentials.env)"
            )
        }

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PanelView(state: state, musicEngine: musicEngine, recorder: recorderController))

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

    /// Deep link huebar://panel — utilisé par le contrôle du Control Center.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "huebar" && $0.host == "panel" }) else { return }
        togglePopover()
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
