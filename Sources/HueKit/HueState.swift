import Foundation
import Observation

public struct RoomModel: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let groupedLightID: String?
    public var isOn: Bool
    public var brightness: Double
    public var scenes: [HueScene]
    public var lights: [Light]
}

public struct AllZone: Sendable, Equatable {
    public let groupedLightID: String
    public var isOn: Bool
    public var scenes: [HueScene]
}

@MainActor
@Observable
public final class HueState {
    public enum Status: Equatable {
        case loading
        case ready
        case error(String)
    }

    public private(set) var status: Status = .loading
    public var all: AllZone?
    public var rooms: [RoomModel] = []

    private let client: (any HueControlling)?
    private let configErrorMessage: String?

    public init(client: (any HueControlling)?, errorMessage: String? = nil) {
        self.client = client
        self.configErrorMessage = errorMessage
    }

    /// Assemble l'arbre pièces -> lampes/scènes à partir des ressources brutes du bridge.
    /// Mapping : room.children contient des device ids ; light.owner.rid est le device id.
    nonisolated static func makeRooms(
        lights: [Light], rooms: [Room], scenes: [HueScene], grouped: [GroupedLight]
    ) -> (all: AllZone?, rooms: [RoomModel]) {
        let groupedByOwner = Dictionary(uniqueKeysWithValues: grouped.map { ($0.owner.rid, $0) })

        let roomModels = rooms.map { room -> RoomModel in
            let deviceIDs = Set(room.children.map(\.rid))
            let groupedLight = groupedByOwner[room.id]
            return RoomModel(
                id: room.id,
                name: room.metadata.name,
                groupedLightID: groupedLight?.id,
                isOn: groupedLight?.on?.on ?? false,
                brightness: groupedLight?.dimming?.brightness ?? 100,
                scenes: scenes.filter { $0.group.rid == room.id },
                lights: lights.filter { deviceIDs.contains($0.owner.rid) }
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let bridgeHome = grouped.first { $0.owner.rtype == "bridge_home" }
        let allZone = bridgeHome.map {
            AllZone(
                groupedLightID: $0.id,
                isOn: $0.on?.on ?? false,
                scenes: scenes.filter { $0.group.rtype == "bridge_home" }
            )
        }
        return (allZone, roomModels)
    }
}
