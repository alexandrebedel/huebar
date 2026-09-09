import Foundation
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Hors bundle .app (dev via `swift run`), SMAppService N'ÉCHOUE PAS : il enregistre
    /// l'exécutable nu du `.build/`, que macOS ouvre ensuite dans Terminal à chaque login
    /// (« …/debug/HueBarApp; exit »). Vécu en réel — on refuse explicitement.
    static var runsFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func set(_ enabled: Bool) {
        guard runsFromAppBundle else {
            NSLog("LoginItem: ignoré hors bundle .app (%@)", Bundle.main.bundleURL.path)
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem: \(error.localizedDescription)")
        }
    }
}
