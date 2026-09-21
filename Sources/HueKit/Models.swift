import Foundation

/// Enveloppe générique des réponses CLIP v2 : {"errors":[...],"data":[...]}
public struct HueResponse<T: Decodable>: Decodable {
    public var data: [T]
}

public struct Metadata: Codable, Sendable, Equatable {
    public var name: String
    /// Image officielle (`public_image`) — présente sur les scènes créées via l'app
    /// Hue, absente de celles créées par API : discrimine les scènes HueBar.
    public var image: ResourceRef?

    public init(name: String, image: ResourceRef? = nil) {
        self.name = name
        self.image = image
    }
}

public struct OnState: Codable, Sendable, Equatable {
    public var on: Bool
    public init(on: Bool) { self.on = on }
}

public struct Dimming: Codable, Sendable, Equatable {
    public var brightness: Double
    public init(brightness: Double) { self.brightness = brightness }

    private enum CodingKeys: String, CodingKey { case brightness }
}

public struct XY: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct ColorState: Codable, Sendable, Equatable {
    public var xy: XY
    public init(xy: XY) { self.xy = xy }

    private enum CodingKeys: String, CodingKey { case xy }
}

public struct ResourceRef: Codable, Sendable, Equatable {
    public var rid: String
    public var rtype: String
    public init(rid: String, rtype: String) { self.rid = rid; self.rtype = rtype }
}

public struct Light: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var metadata: Metadata
    public var on: OnState
    public var dimming: Dimming?
    public var color: ColorState?
    public var owner: ResourceRef
    public var colorTemperature: ColorTemperatureState?
    public var effects: LightEffects?
    public var gradient: GradientState?
    public var effectsV2: LightEffectsV2?

    private enum CodingKeys: String, CodingKey {
        case id, metadata, on, dimming, color, owner, effects, gradient
        case colorTemperature = "color_temperature"
        case effectsV2 = "effects_v2"
    }

    /// Effet en cours (v2 prioritaire : c'est lui qui porte couleur et vitesse), nil si aucun.
    public var activeEffect: String? {
        let effect = effectsV2?.status?.effect ?? effects?.status
        return effect == "no_effect" ? nil : effect
    }
}

public struct Room: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var metadata: Metadata
    public var children: [ResourceRef]
    public var services: [ResourceRef]
}

public struct MirekSchema: Codable, Sendable, Equatable {
    public var mirekMinimum: Int
    public var mirekMaximum: Int

    public init(mirekMinimum: Int, mirekMaximum: Int) {
        self.mirekMinimum = mirekMinimum
        self.mirekMaximum = mirekMaximum
    }

    private enum CodingKeys: String, CodingKey {
        case mirekMinimum = "mirek_minimum"
        case mirekMaximum = "mirek_maximum"
    }
}

public struct ColorTemperatureState: Codable, Sendable, Equatable {
    public var mirek: Int?
    public var mirekSchema: MirekSchema?

    public init(mirek: Int?, mirekSchema: MirekSchema? = nil) {
        self.mirek = mirek
        self.mirekSchema = mirekSchema
    }

    private enum CodingKeys: String, CodingKey {
        case mirek
        case mirekSchema = "mirek_schema"
    }
}

/// Effets natifs d'une lampe (bougie, cheminée, prisme...). En GET, `effectValues`
/// liste les effets supportés ; en PUT seul `effect` est envoyé.
public struct LightEffects: Codable, Sendable, Equatable {
    public var effect: String?
    public var effectValues: [String]?
    public var status: String?

    public init(effect: String? = nil, effectValues: [String]? = nil, status: String? = nil) {
        self.effect = effect
        self.effectValues = effectValues
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case effect
        case effectValues = "effect_values"
        case status
    }
}

/// Effets « v2 » : même catalogue que `effects`, mais l'effet accepte une couleur (ou une
/// température) et une vitesse — une bougie rouge sang plutôt qu'orange. En GET, `action`
/// ne porte que `effect_values` et `status` l'effet en cours avec ses paramètres ; en
/// PUT/POST on envoie `action.effect` + `action.parameters`.
/// RÈGLE DU BRIDGE (vérifiée en réel) : un effet — v1 comme v2 — ne se combine PAS avec
/// `color`/`color_temperature`/`gradient` dans la même action ; la couleur d'un effet
/// passe par `parameters`.
public struct LightEffectsV2: Codable, Sendable, Equatable {
    public struct Temperature: Codable, Sendable, Equatable {
        public var mirek: Int?
        public var mirekValid: Bool?

        public init(mirek: Int?, mirekValid: Bool? = nil) {
            self.mirek = mirek
            self.mirekValid = mirekValid
        }

        private enum CodingKeys: String, CodingKey {
            case mirek
            case mirekValid = "mirek_valid"
        }
    }

    public struct Parameters: Codable, Sendable, Equatable {
        public var color: ColorState?
        public var colorTemperature: Temperature?
        public var speed: Double?

        public init(color: ColorState? = nil, colorTemperature: Temperature? = nil, speed: Double? = nil) {
            self.color = color
            self.colorTemperature = colorTemperature
            self.speed = speed
        }

        private enum CodingKeys: String, CodingKey {
            case color, speed
            case colorTemperature = "color_temperature"
        }
    }

    public struct Action: Codable, Sendable, Equatable {
        public var effect: String?
        public var parameters: Parameters?
        public var effectValues: [String]?

        public init(effect: String?, parameters: Parameters? = nil, effectValues: [String]? = nil) {
            self.effect = effect
            self.parameters = parameters
            self.effectValues = effectValues
        }

        private enum CodingKeys: String, CodingKey {
            case effect, parameters
            case effectValues = "effect_values"
        }
    }

    public struct Status: Codable, Sendable, Equatable {
        public var effect: String?
        public var effectValues: [String]?
        public var parameters: Parameters?

        public init(effect: String?, effectValues: [String]? = nil, parameters: Parameters? = nil) {
            self.effect = effect
            self.effectValues = effectValues
            self.parameters = parameters
        }

        private enum CodingKeys: String, CodingKey {
            case effect, parameters
            case effectValues = "effect_values"
        }
    }

    public var action: Action?
    public var status: Status?

    public init(action: Action? = nil, status: Status? = nil) {
        self.action = action
        self.status = status
    }

    /// Commande d'effet prête à envoyer (PUT lampe ou action de scène).
    public init(effect: String, color: ColorState? = nil, speed: Double? = nil) {
        let parameters = (color == nil && speed == nil) ? nil : Parameters(color: color, speed: speed)
        self.init(action: Action(effect: effect, parameters: parameters))
    }

    /// Effets que la lampe sait jouer en v2 (présents côté `action` ou `status` selon le firmware).
    public var supportedEffects: [String] {
        action?.effectValues ?? status?.effectValues ?? []
    }
}

/// Bandeau gradient (Lightstrip, Play gradient…) : points de couleur répartis sur
/// la longueur. En GET `points` = état courant et `points_capable` = maximum ;
/// en PUT seuls les points sont envoyés.
public struct GradientState: Codable, Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var color: ColorState
        public init(color: ColorState) { self.color = color }
    }

    public var points: [Point]
    public var pointsCapable: Int?

    public init(points: [Point], pointsCapable: Int? = nil) {
        self.points = points
        self.pointsCapable = pointsCapable
    }

    private enum CodingKeys: String, CodingKey {
        case points
        case pointsCapable = "points_capable"
    }
}

/// Action d'une scène : l'état qu'elle appliquera à une lampe.
public struct SceneAction: Codable, Sendable, Equatable {
    /// Lampe cible — présent sur le bridge, requis pour créer une scène.
    public var target: ResourceRef?
    public var action: Body

    public struct Body: Codable, Sendable, Equatable {
        public var on: OnState?
        public var dimming: Dimming?
        public var color: ColorState?
        public var colorTemperature: ColorTemperatureState?
        /// Effet natif (fire, candle…) rejoué par la scène — c'est lui qui scintille.
        /// Jamais avec `color`/`colorTemperature` dans la même action (refus du bridge).
        public var effects: LightEffects?
        /// Effet teinté (couleur + vitesse dans ses paramètres), même règle d'exclusion.
        public var effectsV2: LightEffectsV2?

        public init(
            on: OnState? = nil, dimming: Dimming? = nil,
            color: ColorState? = nil, colorTemperature: ColorTemperatureState? = nil,
            effects: LightEffects? = nil, effectsV2: LightEffectsV2? = nil
        ) {
            self.on = on
            self.dimming = dimming
            self.color = color
            self.colorTemperature = colorTemperature
            self.effects = effects
            self.effectsV2 = effectsV2
        }

        /// L'action joue un effet (v1 ou v2) plutôt qu'un état fixe.
        public var effectName: String? {
            effectsV2?.action?.effect ?? effects?.effect
        }

        private enum CodingKeys: String, CodingKey {
            case on, dimming, color, effects
            case colorTemperature = "color_temperature"
            case effectsV2 = "effects_v2"
        }
    }

    public init(action: Body, target: ResourceRef? = nil) {
        self.action = action
        self.target = target
    }
}

/// Activation d'une scène : "inactive", "static" ou "dynamic_palette".
public struct SceneStatus: Codable, Sendable, Equatable {
    public var active: String?
    public init(active: String?) { self.active = active }
}

/// Palette d'une scène — c'est elle que le mode dynamique fait circuler entre
/// les lampes. Le POST exige les trois tableaux (vides acceptés).
public struct ScenePalette: Codable, Sendable, Equatable {
    public struct ColorEntry: Codable, Sendable, Equatable {
        public var color: ColorState
        public var dimming: Dimming?

        public init(color: ColorState, dimming: Dimming? = nil) {
            self.color = color
            self.dimming = dimming
        }
    }

    public struct TemperatureEntry: Codable, Sendable, Equatable {
        public var colorTemperature: ColorTemperatureState
        public var dimming: Dimming?

        public init(colorTemperature: ColorTemperatureState, dimming: Dimming? = nil) {
            self.colorTemperature = colorTemperature
            self.dimming = dimming
        }

        private enum CodingKeys: String, CodingKey {
            case colorTemperature = "color_temperature"
            case dimming
        }
    }

    public var color: [ColorEntry]?
    public var dimming: [Dimming]?
    public var colorTemperature: [TemperatureEntry]?

    public init(color: [ColorEntry]?, dimming: [Dimming]? = [], colorTemperature: [TemperatureEntry]? = []) {
        self.color = color
        self.dimming = dimming
        self.colorTemperature = colorTemperature
    }

    private enum CodingKeys: String, CodingKey {
        case color, dimming
        case colorTemperature = "color_temperature"
    }
}

public struct HueScene: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var metadata: Metadata
    public var group: ResourceRef
    public var actions: [SceneAction]?
    public var status: SceneStatus?
    public var speed: Double?
    public var palette: ScenePalette?

    public var isActive: Bool {
        if let active = status?.active { active != "inactive" } else { false }
    }

    public var isDynamicActive: Bool { status?.active == "dynamic_palette" }

    /// Jouable en dynamique : il faut au moins deux couleurs à faire circuler.
    public var supportsDynamic: Bool { (palette?.color?.count ?? 0) >= 2 }
}

public struct GroupedLight: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var owner: ResourceRef
    public var on: OnState?
    public var dimming: Dimming?
}

/// Corps des PUT sur light et grouped_light (seuls les champs non-nil sont envoyés).
public struct LightUpdate: Encodable, Sendable, Equatable {
    public var on: OnState?
    public var dimming: Dimming?
    public var color: ColorState?
    public var colorTemperature: ColorTemperatureState?
    public var effects: LightEffects?
    public var gradient: GradientState?
    public var effectsV2: LightEffectsV2?

    public init(
        on: OnState? = nil, dimming: Dimming? = nil, color: ColorState? = nil,
        colorTemperature: ColorTemperatureState? = nil, effects: LightEffects? = nil,
        gradient: GradientState? = nil, effectsV2: LightEffectsV2? = nil
    ) {
        self.on = on
        self.dimming = dimming
        self.color = color
        self.colorTemperature = colorTemperature
        self.effects = effects
        self.gradient = gradient
        self.effectsV2 = effectsV2
    }

    /// L'état qu'applique une action de scène, converti en PUT direct sur la lampe.
    public init(applying body: SceneAction.Body) {
        self.init(
            on: body.on, dimming: body.dimming, color: body.color,
            colorTemperature: body.colorTemperature.map { ColorTemperatureState(mirek: $0.mirek) },
            effects: body.effects.map { LightEffects(effect: $0.effect) },
            effectsV2: body.effectsV2
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(on, forKey: .on)
        try container.encodeIfPresent(dimming, forKey: .dimming)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(colorTemperature, forKey: .colorTemperature)
        try container.encodeIfPresent(effects, forKey: .effects)
        if let gradient {
            // En PUT le bridge refuse points_capable : seuls les points partent.
            try container.encode(GradientState(points: gradient.points), forKey: .gradient)
        }
        if let action = effectsV2?.action {
            // Seule la commande part : ni `status` ni `effect_values` (lecture seule).
            try container.encode(
                LightEffectsV2(action: .init(effect: action.effect, parameters: action.parameters)),
                forKey: .effectsV2)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case on, dimming, color, effects, gradient
        case colorTemperature = "color_temperature"
        case effectsV2 = "effects_v2"
    }
}
