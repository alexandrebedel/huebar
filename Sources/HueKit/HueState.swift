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

    // MARK: - Chargement

    public func refresh() async {
        guard let client else {
            status = .error(configErrorMessage ?? "Non configuré")
            return
        }
        do {
            async let lights = client.fetchLights()
            async let rooms = client.fetchRooms()
            async let scenes = client.fetchScenes()
            async let grouped = client.fetchGroupedLights()
            let built = Self.makeRooms(
                lights: try await lights, rooms: try await rooms,
                scenes: try await scenes, grouped: try await grouped
            )
            self.all = built.all
            self.rooms = built.rooms
            self.status = .ready
        } catch {
            status = .error("Bridge injoignable")
        }
    }

    // MARK: - Actions (optimistes : mutation locale immédiate, resync si échec)

    public func toggleAll() async {
        guard var zone = all else { return }
        zone.isOn.toggle()
        all = zone
        await perform { [id = zone.groupedLightID, on = zone.isOn] client in
            try await client.updateGroupedLight(id: id, LightUpdate(on: OnState(on: on)))
        }
    }

    public func toggleRoom(id: String) async {
        guard let index = rooms.firstIndex(where: { $0.id == id }),
              let groupedID = rooms[index].groupedLightID else { return }
        rooms[index].isOn.toggle()
        await perform { [on = rooms[index].isOn] client in
            try await client.updateGroupedLight(id: groupedID, LightUpdate(on: OnState(on: on)))
        }
    }

    public func setRoomBrightness(id: String, _ brightness: Double) async {
        guard let index = rooms.firstIndex(where: { $0.id == id }),
              let groupedID = rooms[index].groupedLightID else { return }
        rooms[index].brightness = brightness
        rooms[index].isOn = true
        await perform { client in
            try await client.updateGroupedLight(
                id: groupedID,
                LightUpdate(on: OnState(on: true), dimming: Dimming(brightness: brightness))
            )
        }
    }

    public func recallScene(id: String) async {
        await perform { client in
            try await client.recallScene(id: id)
        }
        await refresh() // une scène change lampes et couleurs : on resynchronise tout
    }

    public func toggleLight(roomID: String, lightID: String) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        rooms[roomIndex].lights[lightIndex].on.on.toggle()
        await perform { [on = rooms[roomIndex].lights[lightIndex].on.on] client in
            try await client.updateLight(id: lightID, LightUpdate(on: OnState(on: on)))
        }
    }

    public func setLightBrightness(roomID: String, lightID: String, _ brightness: Double) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        rooms[roomIndex].lights[lightIndex].dimming = Dimming(brightness: brightness)
        rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        await perform { client in
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), dimming: Dimming(brightness: brightness))
            )
        }
    }

    public func setLightColor(roomID: String, lightID: String, red: Double, green: Double, blue: Double) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        let xy = HueColor.xy(red: red, green: green, blue: blue)
        rooms[roomIndex].lights[lightIndex].color = ColorState(xy: xy)
        rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        await perform { client in
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), color: ColorState(xy: xy))
            )
        }
    }

    // MARK: - Helpers

    private func lightIndices(roomID: String, lightID: String) -> (Int, Int)? {
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }),
              let lightIndex = rooms[roomIndex].lights.firstIndex(where: { $0.id == lightID })
        else { return nil }
        return (roomIndex, lightIndex)
    }

    /// Exécute une commande ; en cas d'échec, resynchronise tout (refresh pose le bon status).
    private func perform(_ operation: (any HueControlling) async throws -> Void) async {
        guard let client else { return }
        do {
            try await operation(client)
            if status != .ready { status = .ready }
        } catch {
            await refresh()
        }
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
