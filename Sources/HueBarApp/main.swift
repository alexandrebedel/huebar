import AppKit

// Le point d'entrée s'exécute sur le main thread : l'isolation MainActor est garantie.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
