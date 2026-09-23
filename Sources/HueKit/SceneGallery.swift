import Foundation

/// Galerie de scénarios façon app Hue. Les images/palettes officielles ne sont pas
/// servies par l'API : palettes recréées localement, fidèles aux ambiances connues.
public struct GalleryScenario: Identifiable, Sendable, Equatable {
    public struct RGB: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public enum Kind: Sendable, Equatable {
        /// Couleurs distribuées en boucle sur les lampes de la pièce.
        case palette([RGB])
        /// Recette de blanc (température unique pour toute la pièce).
        case white(mirek: Int)
    }

    /// Rayon de la galerie (filtre en tête de la vue).
    public enum Category: String, Sendable, CaseIterable, Identifiable {
        case ambiance, horror, white

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .ambiance: "Ambiances"
            case .horror: "Horreur"
            case .white: "Blancs"
            }
        }
    }

    public let name: String
    public let kind: Kind
    public let brightness: Double
    /// Effet natif demandé aux lampes qui le supportent (repli sur `candle`, puis
    /// couleur fixe) — c'est ce qui fait scintiller « Feu de camp ».
    public var effect: String? = nil
    /// L'effet prend la couleur de palette de la lampe (`effects_v2`) : une bougie rouge
    /// sang plutôt qu'orange. Sans support v2 sur la lampe, on garde la couleur fixe —
    /// la teinte compte plus que le vacillement.
    public var tintsEffect = false
    /// Vitesse de l'effet teinté (0 lent … 1 rapide) ; nil = défaut du firmware.
    public var effectSpeed: Double? = nil
    public var category: Category = .ambiance

    public var id: String { name }
    public var isAnimated: Bool { effect != nil }

    /// Couleurs d'aperçu pour la carte (les blancs passent par mirek -> RGB).
    public var previewColors: [RGB] {
        switch kind {
        case .palette(let colors): colors
        case .white(let mirek):
            [HueColor.rgb(fromMirek: mirek), HueColor.rgb(fromMirek: mirek + 60)]
                .map { RGB($0.red, $0.green, $0.blue) }
        }
    }
}

public enum SceneGallery {
    static let defaultWhiteMirek = 370
    static let fallbackMirekRange = 153...500

    public static let scenarios: [GalleryScenario] = [
        .init(name: "Savane", kind: .palette([
            .init(1, 0.60, 0.15), .init(1, 0.42, 0.10), .init(0.95, 0.75, 0.35), .init(1, 0.30, 0.10),
        ]), brightness: 80),
        .init(name: "Crépuscule tropical", kind: .palette([
            .init(0.55, 0.25, 0.85), .init(0.95, 0.35, 0.55), .init(1, 0.55, 0.25), .init(0.35, 0.20, 0.70),
        ]), brightness: 75),
        .init(name: "Arctique", kind: .palette([
            .init(0.55, 0.80, 1), .init(0.35, 0.60, 0.95), .init(0.80, 0.92, 1), .init(0.45, 0.75, 0.90),
        ]), brightness: 80),
        .init(name: "Printemps", kind: .palette([
            .init(0.65, 0.90, 0.45), .init(1, 0.75, 0.85), .init(0.95, 0.90, 0.55), .init(0.55, 0.85, 0.60),
        ]), brightness: 80),
        .init(name: "Aurore boréale", kind: .palette([
            .init(0.20, 0.95, 0.60), .init(0.25, 0.75, 0.95), .init(0.60, 0.35, 0.95), .init(0.15, 0.85, 0.80),
        ]), brightness: 70),
        .init(name: "Horizon doré", kind: .palette([
            .init(1, 0.72, 0.30), .init(1, 0.55, 0.20), .init(1, 0.85, 0.55), .init(0.95, 0.65, 0.35),
        ]), brightness: 85),
        .init(name: "Honolulu", kind: .palette([
            .init(1, 0.25, 0.55), .init(1, 0.55, 0.20), .init(0.95, 0.80, 0.30), .init(0.90, 0.20, 0.40),
        ]), brightness: 80),
        .init(name: "Palm Beach", kind: .palette([
            .init(1, 0.45, 0.65), .init(0.30, 0.85, 0.80), .init(0.98, 0.85, 0.60), .init(0.95, 0.55, 0.75),
        ]), brightness: 85),
        .init(name: "Malibu pink", kind: .palette([
            .init(1, 0.30, 0.70), .init(0.85, 0.25, 0.95), .init(0.45, 0.45, 1), .init(1, 0.50, 0.80),
        ]), brightness: 80),
        .init(name: "Soho", kind: .palette([
            .init(0.90, 0.20, 0.80), .init(0.55, 0.15, 0.90), .init(0.20, 0.25, 0.75), .init(1, 0.35, 0.60),
        ]), brightness: 70),
        .init(name: "Rio", kind: .palette([
            .init(1, 0.55, 0.15), .init(1, 0.30, 0.50), .init(0.70, 0.25, 0.90), .init(1, 0.75, 0.25),
        ]), brightness: 85),
        .init(name: "Tokyo", kind: .palette([
            .init(0.25, 0.55, 1), .init(1, 0.25, 0.75), .init(0.40, 0.90, 1), .init(0.80, 0.35, 1),
        ]), brightness: 75),
        .init(name: "Chinatown", kind: .palette([
            .init(1, 0.20, 0.20), .init(1, 0.45, 0.15), .init(1, 0.30, 0.50), .init(0.95, 0.60, 0.20),
        ]), brightness: 80),
        .init(name: "Fête foraine", kind: .palette([
            .init(1, 0.25, 0.25), .init(0.25, 0.60, 1), .init(1, 0.85, 0.20), .init(0.30, 0.90, 0.45),
        ]), brightness: 90),
        // Scintille : effet natif `fire` (repli `candle`) par-dessus une palette de braises.
        .init(name: "Feu de camp", kind: .palette([
            .init(1, 0.35, 0.05), .init(1, 0.18, 0.04), .init(1, 0.55, 0.12), .init(0.95, 0.12, 0.02),
        ]), brightness: 65, effect: "fire"),
        // Soirée film d'horreur : tout est TAMISÉ (la pièce ne doit pas laver l'écran).
        // Rouge sang qui scintille : bougie teintée par la palette (effects_v2). Réglé en
        // réel : à 0.25 le vacillement ne se voyait pas à 14 %, à 0.8 il bougeait trop vite.
        .init(name: "Film d'horreur", kind: .palette([
            .init(1, 0.05, 0.02), .init(0.85, 0, 0.05), .init(1, 0.10, 0), .init(0.70, 0, 0.12),
        ]), brightness: 14, effect: "candle", tintsEffect: true, effectSpeed: 0.5, category: .horror),
        // Vraies bougies (couleur naturelle de l'effet) dans une grande maison vide.
        .init(name: "Manoir hanté", kind: .palette([
            .init(1, 0.62, 0.22), .init(1, 0.55, 0.15), .init(0.95, 0.68, 0.30), .init(1, 0.50, 0.12),
        ]), brightness: 20, effect: "candle", category: .horror),
        // Nuit américaine des slashers : bleu froid, fixe, presque éteint.
        .init(name: "Clair de lune", kind: .palette([
            .init(0.25, 0.40, 1), .init(0.35, 0.55, 1), .init(0.18, 0.30, 0.90), .init(0.45, 0.65, 1),
        ]), brightness: 12, category: .horror),
        // Argento / Suspiria : primaires saturées, une couleur par lampe.
        .init(name: "Giallo", kind: .palette([
            .init(1, 0.05, 0.10), .init(0.10, 0.15, 1), .init(1, 0, 0.55), .init(0, 0.85, 0.35),
        ]), brightness: 35, category: .horror),
        // Vert maladif, néon fatigué qui tremble (labo abandonné, zombies).
        .init(name: "Toxique", kind: .palette([
            .init(0.35, 1, 0.10), .init(0.15, 0.85, 0.25), .init(0.55, 1, 0), .init(0.10, 0.70, 0.30),
        ]), brightness: 16, effect: "candle", tintsEffect: true, effectSpeed: 0.6, category: .horror),
        // Recettes de blanc officielles Hue.
        .init(name: "Détente", kind: .white(mirek: 447), brightness: 56, category: .white),
        .init(name: "Lecture", kind: .white(mirek: 346), brightness: 100, category: .white),
        .init(name: "Concentration", kind: .white(mirek: 233), brightness: 100, category: .white),
        .init(name: "Stimulation", kind: .white(mirek: 156), brightness: 100, category: .white),
    ]

    /// Palette bridge du scénario — rend la scène créée jouable en dynamique ;
    /// nil pour les recettes de blanc et pour les scénarios animés (un effet natif
    /// anime déjà la lampe : le mode dynamique n'a pas de sens par-dessus).
    public static func palette(for scenario: GalleryScenario) -> ScenePalette? {
        guard scenario.effect == nil,
              case .palette(let colors) = scenario.kind, colors.count >= 2 else { return nil }
        return ScenePalette(color: colors.prefix(9).map {
            .init(color: ColorState(xy: HueColor.xy(red: $0.red, green: $0.green, blue: $0.blue)),
                  dimming: Dimming(brightness: scenario.brightness))
        })
    }

    /// Actions par lampe pour un scénario : palette distribuée en boucle sur les lampes
    /// couleur (blanc chaud pour les autres), ou température clampée au schéma de chaque
    /// lampe pour une recette de blanc.
    /// RÈGLE DU BRIDGE (vérifiée en réel, HTTP 400 sinon) : un effet ne se combine pas avec
    /// `color`/`color_temperature` dans la même action. Une lampe reçoit donc SOIT l'effet
    /// (teinté via ses paramètres si le scénario le demande), SOIT son état fixe.
    public static func actions(for scenario: GalleryScenario, lights: [Light]) -> [SceneAction] {
        var colorIndex = 0
        return lights.map { light in
            var body = SceneAction.Body(on: OnState(on: true))
            if light.dimming != nil {
                body.dimming = Dimming(brightness: scenario.brightness)
            }

            var color: ColorState?
            var temperature: ColorTemperatureState?
            switch scenario.kind {
            case .palette(let colors):
                if light.color != nil, !colors.isEmpty {
                    let rgb = colors[colorIndex % colors.count]
                    colorIndex += 1
                    color = ColorState(xy: HueColor.xy(red: rgb.red, green: rgb.green, blue: rgb.blue))
                } else if light.colorTemperature != nil {
                    temperature = ColorTemperatureState(mirek: defaultWhiteMirek)
                }
            case .white(let mirek):
                if let schema = light.colorTemperature?.mirekSchema {
                    temperature = ColorTemperatureState(
                        mirek: min(max(mirek, schema.mirekMinimum), schema.mirekMaximum))
                } else if light.colorTemperature != nil {
                    temperature = ColorTemperatureState(
                        mirek: min(max(mirek, fallbackMirekRange.lowerBound), fallbackMirekRange.upperBound))
                } else if light.color != nil {
                    let rgb = HueColor.rgb(fromMirek: mirek)
                    color = ColorState(xy: HueColor.xy(red: rgb.red, green: rgb.green, blue: rgb.blue))
                }
            }

            if let tinted = tintedEffect(for: scenario, light: light, color: color) {
                body.effectsV2 = tinted
            } else if let native = nativeEffect(for: scenario, light: light) {
                body.effects = native
            } else {
                body.color = color
                body.colorTemperature = temperature
            }
            return SceneAction(action: body, target: ResourceRef(rid: light.id, rtype: "light"))
        }
    }

    /// Effet teinté par la couleur de palette de la lampe — exige `effects_v2` sur la lampe.
    private static func tintedEffect(
        for scenario: GalleryScenario, light: Light, color: ColorState?
    ) -> LightEffectsV2? {
        guard scenario.tintsEffect, let effect = scenario.effect, let color,
              light.effectsV2?.supportedEffects.contains(effect) == true else { return nil }
        return LightEffectsV2(effect: effect, color: color, speed: scenario.effectSpeed)
    }

    /// Effet dans sa couleur naturelle (feu, bougie) ; repli `candle` si la lampe n'a pas
    /// l'effet demandé. Un scénario teinté n'y a pas droit : sa couleur prime.
    private static func nativeEffect(for scenario: GalleryScenario, light: Light) -> LightEffects? {
        guard !scenario.tintsEffect, let effect = scenario.effect,
              let supported = light.effects?.effectValues else { return nil }
        if supported.contains(effect) { return LightEffects(effect: effect) }
        if supported.contains("candle") { return LightEffects(effect: "candle") }
        return nil
    }
}