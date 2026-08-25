import Foundation

/// Couleurs d'aperçu d'une scène, construites depuis ses actions.
/// L'API ne sert pas les images officielles des scènes (`public_image` est un
/// identifiant non téléchargeable) : on génère un dégradé avec les vraies couleurs.
public enum SceneGradient {
    public struct Stop: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Stops dans l'ordre des actions du bridge (stable), lampes éteintes ignorées,
    /// doublons consécutifs fusionnés, plafonné à 5. Blanc chaud si rien d'exploitable.
    public static func stops(for scene: HueScene) -> [Stop] {
        var result: [Stop] = []
        for sceneAction in scene.actions ?? [] {
            let body = sceneAction.action
            if body.on?.on == false { continue }

            let stop: Stop?
            if let xy = body.color?.xy {
                let rgb = HueColor.rgb(from: xy)
                stop = Stop(red: rgb.red, green: rgb.green, blue: rgb.blue)
            } else if let mirek = body.colorTemperature?.mirek {
                let rgb = HueColor.rgb(fromMirek: mirek)
                stop = Stop(red: rgb.red, green: rgb.green, blue: rgb.blue)
            } else {
                stop = nil
            }

            if let stop, stop != result.last {
                result.append(stop)
                if result.count == 5 { break }
            }
        }
        if result.isEmpty {
            result = [Stop(red: 1.0, green: 0.84, blue: 0.62)] // blanc chaud
        }
        return result
    }
}
