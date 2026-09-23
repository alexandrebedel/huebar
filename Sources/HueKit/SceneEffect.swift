import Foundation

/// Réglage de l'effet d'une scène animée (bougie, feu…) depuis l'app : type d'effet,
/// vitesse et luminosité, réécrits dans les actions de la scène sur le bridge.
/// Le firmware n'expose AUCUNE amplitude : le « contraste » d'un vacillement se règle
/// par le choix de l'effet (la cheminée creuse plus que la bougie) et la luminosité.
public struct SceneEffectSettings: Sendable, Equatable {
    public var effect: String
    /// 0 lent … 1 rapide — effets v2 seulement (l'ancien `effects` n'a pas de vitesse).
    public var speed: Double
    public var brightness: Double

    static let defaultSpeed = 0.5

    public init(effect: String, speed: Double, brightness: Double) {
        self.effect = effect
        self.speed = speed
        self.brightness = brightness
    }

    /// Lu sur la première action animée de la scène ; nil si elle ne joue aucun effet.
    public init?(scene: HueScene) {
        guard let body = scene.actions?.first(where: { $0.action.effectName != nil })?.action,
              let effect = body.effectName else { return nil }
        self.init(
            effect: effect,
            speed: body.effectsV2?.action?.parameters?.speed ?? Self.defaultSpeed,
            brightness: body.dimming?.brightness ?? 100)
    }

    /// La vitesse ne s'applique qu'aux effets v2 : sans eux, pas de slider.
    public static func hasSpeed(_ scene: HueScene) -> Bool {
        scene.actions?.contains { $0.action.effectsV2?.action?.effect != nil } ?? false
    }

    /// Actions réécrites : chaque lampe animée prend l'effet (et la vitesse en v2, sa
    /// teinte est gardée), chaque lampe allumée la luminosité. Les lampes fixes gardent
    /// leur état : jamais de couleur à côté d'un effet (refus du bridge).
    public func applied(to actions: [SceneAction]) -> [SceneAction] {
        actions.map { action in
            var action = action
            if var command = action.action.effectsV2?.action, command.effect != nil {
                command.effect = effect
                var parameters = command.parameters ?? LightEffectsV2.Parameters()
                parameters.speed = speed
                command.parameters = parameters
                action.action.effectsV2 = LightEffectsV2(action: command)
            } else if action.action.effects?.effect != nil {
                action.action.effects = LightEffects(effect: effect)
            }
            if action.action.on?.on == true, action.action.dimming != nil {
                action.action.dimming = Dimming(brightness: brightness)
            }
            return action
        }
    }

    /// Effets proposables : ceux que TOUTES les lampes animées de la scène savent jouer
    /// (sinon le bridge refuserait l'action), dans l'ordre du firmware.
    public static func availableEffects(for scene: HueScene, lights: [Light]) -> [String] {
        let lightsByID = Dictionary(lights.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var available: [String]?
        for action in scene.actions ?? [] where action.action.effectName != nil {
            guard let lightID = action.target?.rid, let light = lightsByID[lightID] else { continue }
            let supported = action.action.effectsV2 != nil
                ? light.effectsV2?.supportedEffects ?? []
                : light.effects?.effectValues ?? []
            available = (available ?? supported).filter(supported.contains)
        }
        return (available ?? []).filter { $0 != "no_effect" }
    }
}
