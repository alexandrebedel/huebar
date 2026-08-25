import AppIntents

/// Pont vers l'app : l'AppDelegate branche ici l'ouverture de la fenêtre.
/// Dans l'extension le hook reste nil — sans conséquence : `supportedModes: .foreground`
/// fait exécuter l'intent DANS l'app par le système.
@MainActor
enum PanelOpener {
    static var open: (() -> Void)?
}

/// Compilé dans l'app ET l'extension (cf. project.yml). L'app doit contenir l'intent
/// (Metadata.appintents) : un intent `.foreground` présent uniquement dans l'extension
/// est abandonné en silence au clic du contrôle — c'était le bug du Control Center.
@available(macOS 26.0, *)
struct OpenPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir le panneau HueBar"
    static let isDiscoverable: Bool = false
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        PanelOpener.open?()
        return .result()
    }
}
