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
}

public struct Room: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var metadata: Metadata
    public var children: [ResourceRef]
    public var services: [ResourceRef]
}

public struct ColorTemperatureState: Codable, Sendable, Equatable {
    public var mirek: Int?
    public init(mirek: Int?) { self.mirek = mirek }
}

/// Action d'une scène : l'état qu'elle appliquera à une lampe (sous-ensemble affichage).
public struct SceneAction: Codable, Sendable, Equatable {
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

    public init(action: Body) { self.action = action }
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

    public init(on: OnState? = nil, dimming: Dimming? = nil, color: ColorState? = nil) {
        self.on = on
        self.dimming = dimming
        self.color = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(on, forKey: .on)
        try container.encodeIfPresent(dimming, forKey: .dimming)
        try container.encodeIfPresent(color, forKey: .color)
    }

    private enum CodingKeys: String, CodingKey { case on, dimming, color }
}
