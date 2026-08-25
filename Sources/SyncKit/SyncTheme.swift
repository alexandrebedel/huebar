import Foundation

/// Palette de teintes imposée au mapper — le « thème » visuel de la sync,
/// indépendant du mode (Club/Chill).
public enum SyncTheme: String, Sendable, CaseIterable, Identifiable {
    case spectre // roue libre, tout le spectre
    case neon    // magenta / cyan / violet
    case sunset  // orange / rose / pourpre
    case ocean   // bleus / turquoise / vert d'eau

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .spectre: "Spectre"
        case .neon: "Néon"
        case .sunset: "Sunset"
        case .ocean: "Océan"
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
        }
    }
}
