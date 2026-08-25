import Foundation

/// Capture l'état ACTUEL des lampes d'une pièce en actions de scène : on règle
/// l'ambiance à la main, puis on la fige en vraie scène Hue.
public enum SceneCapture {
    /// Une lampe éteinte est capturée éteinte ; une lampe allumée capture sa
    /// luminosité et son mode couleur courant. Mirek non-nil = mode température
    /// (le bridge met mirek à null quand la lampe est en couleur), sinon xy.
    public static func actions(from lights: [Light]) -> [SceneAction] {
        lights.map { light in
            var body = SceneAction.Body(on: OnState(on: light.on.on))
            if light.on.on {
                if let dimming = light.dimming {
                    body.dimming = dimming
                }
                if let mirek = light.colorTemperature?.mirek {
                    body.colorTemperature = ColorTemperatureState(mirek: mirek)
                } else if let color = light.color {
                    body.color = color
                }
            }
            return SceneAction(action: body, target: ResourceRef(rid: light.id, rtype: "light"))
        }
    }

    /// Palette tirée des couleurs capturées (lampes allumées en mode couleur) —
    /// rend la scène capturée jouable en dynamique dès qu'il y a deux couleurs.
    public static func palette(from actions: [SceneAction]) -> ScenePalette? {
        let entries = actions.compactMap { action -> ScenePalette.ColorEntry? in
            guard action.action.on?.on == true, let color = action.action.color else { return nil }
            return .init(color: color, dimming: action.action.dimming)
        }
        guard entries.count >= 2 else { return nil }
        return ScenePalette(color: Array(entries.prefix(9)))
    }
}
