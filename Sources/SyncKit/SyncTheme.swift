import Foundation

/// Palette de teintes imposée au mapper — le « thème » visuel de la sync,
/// indépendant du mode (Club/Chill).
public enum SyncTheme: String, Sendable, CaseIterable, Identifiable {
    case spectre // roue libre, tout le spectre
    case neon    // magenta / cyan / violet
    case sunset  // orange / rose / pourpre
    case ocean   // bleus / turquoise / vert d'eau
    case ambre   // ors / jaunes chauds — le plus clair
    case braise  // rouges / oranges feu
    case blush   // roses chauds / pêche

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .spectre: "Spectre"
        case .neon: "Néon"
        case .sunset: "Sunset"
        case .ocean: "Océan"
        case .ambre: "Ambre"
        case .braise: "Braise"
        case .blush: "Blush"
        }
    }

    /// Ancres de teinte (0...1) vers lesquelles le mapper attire ses couleurs ;
    /// nil = aucune contrainte (spectre complet).
    public var hueAnchors: [Double]? {
        switch self {
        case .spectre: nil
        case .neon: [0.83, 0.50, 0.72, 0.58]
        case .sunset: [0.03, 0.93, 0.08, 0.85]
        case .ocean: [0.55, 0.48, 0.62, 0.42]
        case .ambre: [0.06, 0.10, 0.13, 0.04]
        case .braise: [0.00, 0.04, 0.96, 0.07]
        case .blush: [0.93, 0.97, 0.02, 0.88]
        }
    }
}
