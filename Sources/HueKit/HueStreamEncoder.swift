import Foundation

/// Couleur RGB (0...1) pour un channel de la zone Entertainment.
public struct ChannelColor: Sendable, Equatable {
    public var channel: UInt8
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(channel: UInt8, red: Double, green: Double, blue: Double) {
        self.channel = channel
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Encode les datagrammes du protocole HueStream v2 (mode RGB).
/// Layout : "HueStream" + version 2.0 + seq + réservé + colorspace + réservé
/// + id de configuration (36 chars ASCII) + 7 octets par channel (id + R,G,B uint16 big-endian).
public enum HueStreamEncoder {
    public static func frame(configID: String, sequence: UInt8, channels: [ChannelColor]) -> Data {
        var data = Data(capacity: 52 + channels.count * 7)
        data.append(contentsOf: Array("HueStream".utf8))
        data.append(contentsOf: [0x02, 0x00, sequence, 0x00, 0x00, 0x00, 0x00])
        data.append(contentsOf: Array(configID.utf8.prefix(36)))
        for color in channels.sorted(by: { $0.channel < $1.channel }) {
            data.append(color.channel)
            appendValue(color.red, to: &data)
            appendValue(color.green, to: &data)
            appendValue(color.blue, to: &data)
        }
        return data
    }

    private static func appendValue(_ value: Double, to data: inout Data) {
        let scaled = UInt16((min(max(value, 0), 1) * 65535).rounded())
        data.append(UInt8(scaled >> 8))
        data.append(UInt8(scaled & 0xFF))
    }
}
