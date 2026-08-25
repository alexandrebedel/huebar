import Foundation
import Observation

public struct RoomModel: Identifiable, Sendable, Equatable {
    public let id: String
    public var name: String
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
            try await load(client)
        } catch {
            // Premier hit à froid : un retry silencieux évite un « Bridge injoignable »
            // gratuit au lancement (le clic « Réessayer » marchait toujours du premier coup).
            try? await Task.sleep(for: .milliseconds(700))
            do {
                try await load(client)
            } catch {
                status = .error("Bridge injoignable")
            }
        }
    }

    private func load(_ client: any HueControlling) async throws {
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
        // Le PUT grouped_light applique on+dimming à TOUTES les lampes : on le reflète
        // localement pour que les sliders des lampes (et la moyenne) suivent sans refresh.
        for lightIndex in rooms[index].lights.indices {
            rooms[index].lights[lightIndex].on = OnState(on: true)
            if rooms[index].lights[lightIndex].dimming != nil {
                rooms[index].lights[lightIndex].dimming = Dimming(brightness: brightness)
            }
        }
        await perform { client in
            try await client.updateGroupedLight(
                id: groupedID,
                LightUpdate(on: OnState(on: true), dimming: Dimming(brightness: brightness))
            )
        }
    }

    /// Couleur de toute la pièce (comme l'app Hue) : le PUT grouped_light l'applique
    /// à toutes les lampes couleur — reflet local, et on:true allume tout le groupe.
    public func setRoomColor(id: String, red: Double, green: Double, blue: Double) async {
        guard let index = rooms.firstIndex(where: { $0.id == id }),
              let groupedID = rooms[index].groupedLightID else { return }
        let xy = HueColor.xy(red: red, green: green, blue: blue)
        rooms[index].isOn = true
        for lightIndex in rooms[index].lights.indices {
            rooms[index].lights[lightIndex].on = OnState(on: true)
            if rooms[index].lights[lightIndex].color != nil {
                rooms[index].lights[lightIndex].color = ColorState(xy: xy)
            }
        }
        await perform { client in
            try await client.updateGroupedLight(
                id: groupedID,
                LightUpdate(on: OnState(on: true), color: ColorState(xy: xy))
            )
        }
    }

    /// Température de toute la pièce ; chaque lampe clampe au besoin sur son schéma.
    public func setRoomTemperature(id: String, mirek: Int) async {
        guard let index = rooms.firstIndex(where: { $0.id == id }),
              let groupedID = rooms[index].groupedLightID else { return }
        rooms[index].isOn = true
        for lightIndex in rooms[index].lights.indices {
            rooms[index].lights[lightIndex].on = OnState(on: true)
            if rooms[index].lights[lightIndex].colorTemperature != nil {
                rooms[index].lights[lightIndex].colorTemperature?.mirek = mirek
            }
        }
        await perform { client in
            try await client.updateGroupedLight(
                id: groupedID,
                LightUpdate(on: OnState(on: true), colorTemperature: ColorTemperatureState(mirek: mirek))
            )
        }
    }

    public func recallScene(id: String) async {
        markSceneActive(id: id) // le highlight suit le clic, le refresh confirmera
        await perform { client in
            try await client.recallScene(id: id)
        }
        await refresh() // une scène change lampes et couleurs : on resynchronise tout
    }

    /// La scène rappelée devient active, les autres scènes du même groupe inactives.
    private func markSceneActive(id: String) {
        for roomIndex in rooms.indices where rooms[roomIndex].scenes.contains(where: { $0.id == id }) {
            for sceneIndex in rooms[roomIndex].scenes.indices {
                rooms[roomIndex].scenes[sceneIndex].status = SceneStatus(
                    active: rooms[roomIndex].scenes[sceneIndex].id == id ? "static" : "inactive")
            }
        }
        if var zone = all, zone.scenes.contains(where: { $0.id == id }) {
            for index in zone.scenes.indices {
                zone.scenes[index].status = SceneStatus(
                    active: zone.scenes[index].id == id ? "static" : "inactive")
            }
            all = zone
        }
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

    public func setLightTemperature(roomID: String, lightID: String, mirek: Int) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        rooms[roomIndex].lights[lightIndex].colorTemperature?.mirek = mirek
        rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        await perform { client in
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), colorTemperature: ColorTemperatureState(mirek: mirek))
            )
        }
    }

    public func setLightEffect(roomID: String, lightID: String, effect: String) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        rooms[roomIndex].lights[lightIndex].effects?.status = effect
        if effect != "no_effect" {
            rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        }
        await perform { client in
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), effects: LightEffects(effect: effect))
            )
        }
    }

    /// Applique un scénario de la galerie aux lampes d'une pièce (sans créer de scène).
    public func applyScenario(roomID: String, _ scenario: GalleryScenario) async {
        guard let roomIndex = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        let actions = SceneGallery.actions(for: scenario, lights: rooms[roomIndex].lights)
        for action in actions {
            guard let lightID = action.target?.rid,
                  let lightIndex = rooms[roomIndex].lights.firstIndex(where: { $0.id == lightID })
            else { continue }
            rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
            if let dimming = action.action.dimming {
                rooms[roomIndex].lights[lightIndex].dimming = dimming
            }
            if let color = action.action.color {
                rooms[roomIndex].lights[lightIndex].color = color
            }
            if let mirek = action.action.colorTemperature?.mirek {
                rooms[roomIndex].lights[lightIndex].colorTemperature?.mirek = mirek
            }
        }
        rooms[roomIndex].isOn = true
        await perform { client in
            for action in actions {
                guard let lightID = action.target?.rid else { continue }
                try await client.updateLight(id: lightID, LightUpdate(applying: action.action))
            }
        }
    }

    /// Supprime une scène du bridge (retrait local immédiat).
    public func deleteScene(id: String) async {
        for index in rooms.indices {
            rooms[index].scenes.removeAll { $0.id == id }
        }
        if var zone = all {
            zone.scenes.removeAll { $0.id == id }
            all = zone
        }
        await perform { client in
            try await client.deleteScene(id: id)
        }
    }

    /// Crée le scénario comme vraie scène de la pièce sur le bridge.
    public func saveScenario(roomID: String, _ scenario: GalleryScenario) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let actions = SceneGallery.actions(for: scenario, lights: room.lights)
        guard !actions.isEmpty else { return }
        await perform { client in
            try await client.createScene(name: scenario.name, groupID: roomID, actions: actions)
        }
        await refresh() // la nouvelle scène doit apparaître dans la grille
    }

    // MARK: - Renommage (optimiste, comme le reste)

    public func renameLight(roomID: String, lightID: String, name: String) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        rooms[roomIndex].lights[lightIndex].metadata.name = name
        await perform { client in
            try await client.renameLight(id: lightID, name: name)
        }
    }

    public func renameRoom(id: String, name: String) async {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        rooms[index].name = name
        await perform { client in
            try await client.renameRoom(id: id, name: name)
        }
    }

    public func renameScene(id: String, name: String) async {
        for roomIndex in rooms.indices {
            if let sceneIndex = rooms[roomIndex].scenes.firstIndex(where: { $0.id == id }) {
                rooms[roomIndex].scenes[sceneIndex].metadata.name = name
            }
        }
        if var zone = all, let sceneIndex = zone.scenes.firstIndex(where: { $0.id == id }) {
            zone.scenes[sceneIndex].metadata.name = name
            all = zone
        }
        await perform { client in
            try await client.renameScene(id: id, name: name)
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
        // Ordre du bridge préservé : c'est celui qu'affiche l'app Hue.

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
