import Foundation

/// Capture l'état ACTUEL des lampes d'une pièce en actions de scène : on règle
/// l'ambiance à la main, puis on la fige en vraie scène Hue.
public enum SceneCapture {
    /// Une lampe éteinte est capturée éteinte ; une lampe allumée capture sa
    /// luminosité et son mode couleur courant. Mirek non-nil = mode température
    /// (le bridge met mirek à null quand la lampe est en couleur), sinon xy.
    /// Un effet en cours (bougie, feu…) fait partie de l'ambiance : il est capturé À LA
    /// PLACE de la couleur — le bridge refuse effet + couleur dans la même action.
    public static func actions(from lights: [Light]) -> [SceneAction] {
        lights.map { light in
            var body = SceneAction.Body(on: OnState(on: light.on.on))
            if light.on.on {
                if let dimming = light.dimming {
                    body.dimming = dimming
                }
                if let tinted = activeTintedEffect(of: light) {
                    body.effectsV2 = tinted
                } else if let effect = light.activeEffect {
                    body.effects = LightEffects(effect: effect)
                } else if let mirek = light.colorTemperature?.mirek {
                    body.colorTemperature = ColorTemperatureState(mirek: mirek)
                } else if let color = light.color {
                    body.color = color
                }
            }
            return SceneAction(action: body, target: ResourceRef(rid: light.id, rtype: "light"))
        }
    }

    /// Effet v2 en cours, avec SES paramètres (couleur OU température valide, vitesse) :
    /// la bougie rouge reste rouge dans la scène capturée.
    private static func activeTintedEffect(of light: Light) -> LightEffectsV2? {
        guard let status = light.effectsV2?.status,
              let effect = status.effect, effect != "no_effect" else { return nil }
        var parameters = LightEffectsV2.Parameters(speed: status.parameters?.speed)
        if let temperature = status.parameters?.colorTemperature,
           temperature.mirekValid == true, let mirek = temperature.mirek {
            parameters.colorTemperature = LightEffectsV2.Temperature(mirek: mirek)
        } else {
            parameters.color = status.parameters?.color
        }
        let isEmpty = parameters.color == nil && parameters.colorTemperature == nil && parameters.speed == nil
        return LightEffectsV2(action: .init(effect: effect, parameters: isEmpty ? nil : parameters))
    }

    /// Palette tirée des couleurs capturées (lampes allumées en mode couleur) —
    /// rend la scène capturée jouable en dynamique dès qu'il y a deux couleurs.
    public static func palette(from actions: [SceneAction]) -> ScenePalette? {
        // Une scène à effets est déjà animée : pas de palette (ni de mode dynamique) par-dessus.
        guard !actions.contains(where: { $0.action.effectName != nil }) else { return nil }
        let entries = actions.compactMap { action -> ScenePalette.ColorEntry? in
            guard action.action.on?.on == true, let color = action.action.color else { return nil }
            return .init(color: color, dimming: action.action.dimming)
        }
        guard entries.count >= 2 else { return nil }
        return ScenePalette(color: Array(entries.prefix(9)))
    }
}
