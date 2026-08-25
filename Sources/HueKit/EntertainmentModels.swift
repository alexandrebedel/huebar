import Foundation

/// Zone Entertainment (streaming) telle qu'exposée par CLIP v2.
public struct EntertainmentConfig: Codable, Identifiable, Sendable, Equatable {
    public struct Position: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double
        public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    }

    public struct Channel: Codable, Sendable, Equatable {
        public var channelID: UInt8
        public var position: Position

        private enum CodingKeys: String, CodingKey {
            case channelID = "channel_id"
            case position
        }

        public init(channelID: UInt8, position: Position) {
            self.channelID = channelID
            self.position = position
        }
    }

    public var id: String
    public var metadata: Metadata
    public var status: String
    public var channels: [Channel]
}

/// Accès Entertainment du bridge (REST) — séparé de HueControlling pour ne pas
/// imposer le streaming aux consommateurs du panneau classique.
public protocol EntertainmentControlling: Sendable {
    func fetchEntertainmentConfigurations() async throws -> [EntertainmentConfig]
    func startEntertainment(id: String) async throws
    func stopEntertainment(id: String) async throws
    func fetchApplicationID() async throws -> String
}
