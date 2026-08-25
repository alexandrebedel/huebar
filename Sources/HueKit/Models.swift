import Foundation

/// Enveloppe générique des réponses CLIP v2 : {"errors":[...],"data":[...]}
public struct HueResponse<T: Decodable>: Decodable {
    public var data: [T]
}

public struct Metadata: Codable, Sendable, Equatable {
    public var name: String
    public init(name: String) { self.name = name }
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

    private enum CodingKeys: String, CodingKey {
        case id, metadata, on, dimming, color, owner, effects
        case colorTemperature = "color_temperature"
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

        public init(
            on: OnState? = nil, dimming: Dimming? = nil,
            color: ColorState? = nil, colorTemperature: ColorTemperatureState? = nil
        ) {
            self.on = on
            self.dimming = dimming
            self.color = color
            self.colorTemperature = colorTemperature
        }

        private enum CodingKeys: String, CodingKey {
            case on, dimming, color
            case colorTemperature = "color_temperature"
        }
    }

    public init(action: Body, target: ResourceRef? = nil) {
        self.action = action
        self.target = target
    }
}

public struct HueScene: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var metadata: Metadata
    public var group: ResourceRef
    public var actions: [SceneAction]?
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

    public init(
        on: OnState? = nil, dimming: Dimming? = nil, color: ColorState? = nil,
        colorTemperature: ColorTemperatureState? = nil, effects: LightEffects? = nil
    ) {
        self.on = on
        self.dimming = dimming
        self.color = color
        self.colorTemperature = colorTemperature
        self.effects = effects
    }

    /// L'état qu'applique une action de scène, converti en PUT direct sur la lampe.
    public init(applying body: SceneAction.Body) {
        self.init(
            on: body.on, dimming: body.dimming, color: body.color,
            colorTemperature: body.colorTemperature.map { ColorTemperatureState(mirek: $0.mirek) }
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(on, forKey: .on)
        try container.encodeIfPresent(dimming, forKey: .dimming)
        try container.encodeIfPresent(color, forKey: .color)
        try container.encodeIfPresent(colorTemperature, forKey: .colorTemperature)
        try container.encodeIfPresent(effects, forKey: .effects)
    }

    private enum CodingKeys: String, CodingKey {
        case on, dimming, color, effects
        case colorTemperature = "color_temperature"
    }
}
