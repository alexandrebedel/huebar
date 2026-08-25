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
            let engine = MusicSyncEngine(config: config, entertainment: client, transport: DTLSStreamer())
            // Couplage hors de la vue : un REC accroché à la source de la sync doit être
            // finalisé quand la sync tombe, même popover fermé (la vue ne reçoit alors
            // aucun update SwiftUI).
            engine.onDidTeardown = { [recorderController] in
                if recorderController.isSharingExternalSource {
                    recorderController.stop()
                }
            }
            musicEngine = engine
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

    /// Quitter pendant un enregistrement laisserait un WAV au header non finalisé (illisible),
    /// et un streaming actif verrouillerait la zone du bridge ~10 s : on ferme proprement.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        recorderController.stop() // synchrone : draine et finalise le fichier
        guard let musicEngine, musicEngine.state == .running || musicEngine.state == .starting else {
            return .terminateNow
        }
        Task { @MainActor in
            await musicEngine.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// « Ouvrir au login » actif par défaut, mais on respecte un choix utilisateur ultérieur.
    private func registerLoginItemOnFirstLaunch() {
        let key = "didConfigureLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        LoginItem.set(true)
        UserDefaults.standard.set(true, forKey: key)
    }
}
