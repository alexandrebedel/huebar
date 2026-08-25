import AppKit
import SwiftUI
import HueKit
import SyncKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PanelWindowController!
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
            // finalisé quand la sync tombe, même fenêtre fermée (la vue ne reçoit alors
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

        panel = PanelWindowController(
            rootView: AppWindowView(state: state, musicEngine: musicEngine, recorder: recorderController))
        panel.onShow = { [state] in Task { await state?.refresh() } }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "HueBar")
            button.target = self
            button.action = #selector(togglePanel)
        }

        HotKeyCenter.action = { [weak self] in self?.panel.toggle() }
        hotKeys.register()

        registerLoginItemOnFirstLaunch()
    }

    /// Deep link huebar://panel — quicklink Raycast, scripting.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "huebar" && $0.host == "panel" }) else { return }
        panel.show()
    }

    /// Réouverture (open -a HueBar, Raycast « Open Application ») : montrer la fenêtre.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    @objc private func togglePanel() {
        panel.toggle()
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
