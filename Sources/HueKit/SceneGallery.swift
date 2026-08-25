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

    public let name: String
    public let kind: Kind
    public let brightness: Double

    public var id: String { name }

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
        // Recettes de blanc officielles Hue.
        .init(name: "Détente", kind: .white(mirek: 447), brightness: 56),
        .init(name: "Lecture", kind: .white(mirek: 346), brightness: 100),
        .init(name: "Concentration", kind: .white(mirek: 233), brightness: 100),
        .init(name: "Stimulation", kind: .white(mirek: 156), brightness: 100),
    ]

    /// Actions par lampe pour un scénario : palette distribuée en boucle sur les lampes
    /// couleur (blanc chaud pour les autres), ou température clampée au schéma de chaque
    /// lampe pour une recette de blanc.
    public static func actions(for scenario: GalleryScenario, lights: [Light]) -> [SceneAction] {
        var colorIndex = 0
        return lights.map { light in
            var body = SceneAction.Body(on: OnState(on: true))
            if light.dimming != nil {
                body.dimming = Dimming(brightness: scenario.brightness)
            }
            switch scenario.kind {
            case .palette(let colors):
                if light.color != nil, !colors.isEmpty {
                    let rgb = colors[colorIndex % colors.count]
                    colorIndex += 1
                    body.color = ColorState(xy: HueColor.xy(red: rgb.red, green: rgb.green, blue: rgb.blue))
                } else if light.colorTemperature != nil {
                    body.colorTemperature = ColorTemperatureState(mirek: defaultWhiteMirek)
                }
            case .white(let mirek):
                if let schema = light.colorTemperature?.mirekSchema {
                    body.colorTemperature = ColorTemperatureState(
                        mirek: min(max(mirek, schema.mirekMinimum), schema.mirekMaximum))
                } else if light.colorTemperature != nil {
                    body.colorTemperature = ColorTemperatureState(
                        mirek: min(max(mirek, fallbackMirekRange.lowerBound), fallbackMirekRange.upperBound))
                } else if light.color != nil {
                    let rgb = HueColor.rgb(fromMirek: mirek)
                    body.color = ColorState(xy: HueColor.xy(red: rgb.red, green: rgb.green, blue: rgb.blue))
                }
            }
            return SceneAction(action: body, target: ResourceRef(rid: light.id, rtype: "light"))
        }
    }
}