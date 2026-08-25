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

    public init(sensitivity: Double = 1, punch: Double = 1, flash: Double = 0.30) {
        self.sensitivity = sensitivity
        self.punch = punch
        self.flash = flash
    }

    public static let `default` = SyncTuning()
}
