import Foundation

/// Zone Entertainment (streaming) telle qu'exposée par CLIP v2.
public struct EntertainmentConfig: Codable, Identifiable, Sendable, Equatable {
    public struct Position: Codable, Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var z: Double
        public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    }

    public struct Member: Codable, Sendable, Equatable {
        public var service: ResourceRef
        public init(service: ResourceRef) { self.service = service }
    }

    public struct Channel: Codable, Sendable, Equatable {
        public var channelID: UInt8
        public var position: Position
        /// Services entertainment derrière ce channel — permet de remonter au device,
        /// donc à la pièce.
        public var members: [Member]?

        private enum CodingKeys: String, CodingKey {
            case channelID = "channel_id"
            case position
            case members
        }

        public init(channelID: UInt8, position: Position, members: [Member]? = nil) {
            self.channelID = channelID
            self.position = position
            self.members = members
        }
    }

    public var id: String
    public var metadata: Metadata
    public var status: String
    public var channels: [Channel]
}

/// Service entertainment d'un device (un canal de streaming potentiel).
public struct EntertainmentService: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var owner: ResourceRef

    public init(id: String, owner: ResourceRef) {
        self.id = id
        self.owner = owner
    }
}

/// Accès Entertainment du bridge (REST) — séparé de HueControlling pour ne pas
/// imposer le streaming aux consommateurs du panneau classique.
public protocol EntertainmentControlling: Sendable {
    func fetchEntertainmentConfigurations() async throws -> [EntertainmentConfig]
    func fetchEntertainmentServices() async throws -> [EntertainmentService]
    func startEntertainment(id: String) async throws
    func stopEntertainment(id: String) async throws
    func fetchApplicationID() async throws -> String
}
