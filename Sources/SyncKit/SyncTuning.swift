import Foundation

/// Réglages utilisateur de la sync, appliqués en direct par le mapper (sans reset
/// de son état) — fini les recompilations pour ajuster le feel.
public struct SyncTuning: Sendable, Equatable, Codable {
    /// Multiplie l'énergie perçue : 0.4 discret … 2 très lumineux.
    public var sensitivity: Double
    /// Vitesse d'attaque : 0.5 mou … 2 très sec (divise les constantes d'attack).
    public var punch: Double
    /// Poids du flash sur les beats (Club uniquement), 0 … 0.6.
    public var flash: Double
    /// Master de luminosité appliqué à la sortie : 0.2 tamisé … 2 (les pics saturent
    /// au maximum réel des lampes).
    public var brightness: Double

    public init(sensitivity: Double = 1, punch: Double = 1, flash: Double = 0.30, brightness: Double = 1) {
        self.sensitivity = sensitivity
        self.punch = punch
        self.flash = flash
        self.brightness = brightness
    }

    /// Décodage tolérant : un réglage persisté avant l'ajout d'un champ garde
    /// ses valeurs et prend le défaut pour le reste.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sensitivity = try container.decodeIfPresent(Double.self, forKey: .sensitivity) ?? 1
        punch = try container.decodeIfPresent(Double.self, forKey: .punch) ?? 1
        flash = try container.decodeIfPresent(Double.self, forKey: .flash) ?? 0.30
        brightness = try container.decodeIfPresent(Double.self, forKey: .brightness) ?? 1
    }

    private enum CodingKeys: String, CodingKey {
        case sensitivity, punch, flash, brightness
    }

    public static let `default` = SyncTuning()
}
