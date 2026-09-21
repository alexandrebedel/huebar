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
        let running = takeActiveEffects(roomIndex: index)
        rooms[index].isOn = true
        for lightIndex in rooms[index].lights.indices {
            rooms[index].lights[lightIndex].on = OnState(on: true)
            if rooms[index].lights[lightIndex].color != nil {
                rooms[index].lights[lightIndex].color = ColorState(xy: xy)
            }
        }
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
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
        let running = takeActiveEffects(roomIndex: index)
        rooms[index].isOn = true
        for lightIndex in rooms[index].lights.indices {
            rooms[index].lights[lightIndex].on = OnState(on: true)
            if rooms[index].lights[lightIndex].colorTemperature != nil {
                rooms[index].lights[lightIndex].colorTemperature?.mirek = mirek
            }
        }
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
            try await client.updateGroupedLight(
                id: groupedID,
                LightUpdate(on: OnState(on: true), colorTemperature: ColorTemperatureState(mirek: mirek))
            )
        }
    }

    /// Délai avant le refresh de confirmation d'un recall : le bridge FADE les lampes
    /// (~400 ms et plus) et un fetch immédiat rapportait des couleurs à moitié
    /// transitionnées — des « résidus » de la scène précédente figés dans l'app.
    var recallSettleDelay: Duration = .milliseconds(1200)

    public func recallScene(id: String) async {
        markSceneActive(id: id) // le highlight suit le clic, le refresh confirmera
        let running = applySceneActionsLocally(id: id) // l'état FINAL tout de suite, sans attendre le fade
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
            try await client.recallScene(id: id)
        }
        try? await Task.sleep(for: recallSettleDelay)
        await refresh() // fade terminé : on resynchronise sur l'état réel
    }

    /// Lance la scène en mode dynamique (sa palette circule entre les lampes).
    public func recallSceneDynamic(id: String) async {
        markSceneActive(id: id, as: "dynamic_palette")
        let running = applySceneActionsLocally(id: id)
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
            try await client.recallDynamicScene(id: id)
        }
        try? await Task.sleep(for: recallSettleDelay)
        await refresh()
    }

    /// Peint localement l'état final des actions de la scène — l'app affiche la
    /// scène cible pendant le fade, le refresh confirmera. Renvoie les lampes qu'un effet
    /// animait et que la scène fige : leur effet est à couper avant le recall.
    @discardableResult
    func applySceneActionsLocally(id: String) -> [String] {
        let scene = rooms.flatMap(\.scenes).first { $0.id == id } ?? all?.scenes.first { $0.id == id }
        guard let actions = scene?.actions, !actions.isEmpty else { return [] }
        var effectsToStop: [String] = []
        let bodiesByLightID = Dictionary(
            actions.compactMap { action in action.target.map { ($0.rid, action.action) } },
            uniquingKeysWith: { first, _ in first }
        )
        for roomIndex in rooms.indices {
            var touched = false
            for lightIndex in rooms[roomIndex].lights.indices {
                guard let body = bodiesByLightID[rooms[roomIndex].lights[lightIndex].id] else { continue }
                touched = true
                if let on = body.on {
                    rooms[roomIndex].lights[lightIndex].on = on
                }
                if let dimming = body.dimming {
                    rooms[roomIndex].lights[lightIndex].dimming = dimming
                }
                if let color = body.color {
                    rooms[roomIndex].lights[lightIndex].color = color
                    rooms[roomIndex].lights[lightIndex].colorTemperature?.mirek = nil // mode couleur
                } else if let mirek = body.colorTemperature?.mirek {
                    rooms[roomIndex].lights[lightIndex].colorTemperature?.mirek = mirek
                }
                if let effect = body.effectName {
                    markEffectLocally(effect, roomIndex: roomIndex, lightIndex: lightIndex,
                                      tint: body.effectsV2?.action?.parameters?.color)
                } else if rooms[roomIndex].lights[lightIndex].activeEffect != nil {
                    effectsToStop.append(rooms[roomIndex].lights[lightIndex].id)
                    markEffectLocally("no_effect", roomIndex: roomIndex, lightIndex: lightIndex)
                }
            }
            if touched {
                rooms[roomIndex].isOn = rooms[roomIndex].lights.contains { $0.on.on }
            }
        }
        return effectsToStop
    }

    /// Vitesse du mode dynamique (0 lent ... 1 rapide), mémorisée par scène.
    public func setSceneSpeed(id: String, speed: Double) async {
        for roomIndex in rooms.indices {
            if let sceneIndex = rooms[roomIndex].scenes.firstIndex(where: { $0.id == id }) {
                rooms[roomIndex].scenes[sceneIndex].speed = speed
            }
        }
        if var zone = all, let sceneIndex = zone.scenes.firstIndex(where: { $0.id == id }) {
            zone.scenes[sceneIndex].speed = speed
            all = zone
        }
        await perform { client in
            try await client.setSceneSpeed(id: id, speed: speed)
        }
    }

    /// La scène rappelée devient active, les autres scènes du même groupe inactives.
    private func markSceneActive(id: String, as active: String = "static") {
        for roomIndex in rooms.indices where rooms[roomIndex].scenes.contains(where: { $0.id == id }) {
            for sceneIndex in rooms[roomIndex].scenes.indices {
                rooms[roomIndex].scenes[sceneIndex].status = SceneStatus(
                    active: rooms[roomIndex].scenes[sceneIndex].id == id ? active : "inactive")
            }
        }
        if var zone = all, zone.scenes.contains(where: { $0.id == id }) {
            for index in zone.scenes.indices {
                zone.scenes[index].status = SceneStatus(
                    active: zone.scenes[index].id == id ? active : "inactive")
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
        let running = takeActiveEffects(roomIndex: roomIndex, only: [lightID])
        rooms[roomIndex].lights[lightIndex].color = ColorState(xy: xy)
        rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), color: ColorState(xy: xy))
            )
        }
    }

    public func setLightTemperature(roomID: String, lightID: String, mirek: Int) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        let running = takeActiveEffects(roomIndex: roomIndex, only: [lightID])
        rooms[roomIndex].lights[lightIndex].colorTemperature?.mirek = mirek
        rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), colorTemperature: ColorTemperatureState(mirek: mirek))
            )
        }
    }

    /// Points de couleur d'un bandeau gradient (répartis sur sa longueur).
    public func setLightGradient(
        roomID: String, lightID: String, colors: [(red: Double, green: Double, blue: Double)]
    ) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID),
              rooms[roomIndex].lights[lightIndex].gradient != nil, !colors.isEmpty else { return }
        let points = colors.map {
            GradientState.Point(color: ColorState(xy: HueColor.xy(red: $0.red, green: $0.green, blue: $0.blue)))
        }
        rooms[roomIndex].lights[lightIndex].gradient?.points = points
        rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
        await perform { client in
            try await client.updateLight(
                id: lightID,
                LightUpdate(on: OnState(on: true), gradient: GradientState(points: points))
            )
        }
    }

    /// Effet natif sur toute la pièce : le grouped_light ne porte pas `effects`, on
    /// l'envoie à chaque lampe qui le supporte (les autres sont laissées telles quelles).
    public func setRoomEffect(id: String, effect: String) async {
        guard let roomIndex = rooms.firstIndex(where: { $0.id == id }) else { return }
        var targets: [String] = []
        for lightIndex in rooms[roomIndex].lights.indices {
            guard rooms[roomIndex].lights[lightIndex].effects?.effectValues?.contains(effect) == true
            else { continue }
            markEffectLocally(effect, roomIndex: roomIndex, lightIndex: lightIndex)
            if effect != "no_effect" {
                rooms[roomIndex].lights[lightIndex].on = OnState(on: true)
            }
            targets.append(rooms[roomIndex].lights[lightIndex].id)
        }
        guard !targets.isEmpty else { return }
        if effect != "no_effect" { rooms[roomIndex].isOn = true }
        await perform { client in
            for lightID in targets {
                try await client.updateLight(
                    id: lightID,
                    LightUpdate(on: effect == "no_effect" ? nil : OnState(on: true),
                                effects: LightEffects(effect: effect))
                )
            }
        }
    }

    public func setLightEffect(roomID: String, lightID: String, effect: String) async {
        guard let (roomIndex, lightIndex) = lightIndices(roomID: roomID, lightID: lightID) else { return }
        markEffectLocally(effect, roomIndex: roomIndex, lightIndex: lightIndex)
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
        // Lampes animées par un effet que ce scénario fige sur un état fixe : leur effet
        // est à couper avant (les lampes qui reçoivent un nouvel effet le remplacent d'office).
        let frozen = Set(actions.filter { $0.action.effectName == nil }.compactMap { $0.target?.rid })
        let running = takeActiveEffects(roomIndex: roomIndex, only: frozen)
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
            if let effect = action.action.effectName {
                markEffectLocally(effect, roomIndex: roomIndex, lightIndex: lightIndex,
                                  tint: action.action.effectsV2?.action?.parameters?.color)
            }
        }
        rooms[roomIndex].isOn = true
        await perform { client in
            try await Self.stopEffects(on: running, with: client)
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

    /// Fige l'état actuel des lampes de la pièce en vraie scène sur le bridge.
    public func captureScene(roomID: String, name: String) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let actions = SceneCapture.actions(from: room.lights)
        guard !actions.isEmpty else { return }
        await perform { client in
            try await client.createScene(
                name: name, groupID: roomID, actions: actions,
                palette: SceneCapture.palette(from: actions))
        }
        await refresh() // la nouvelle scène doit apparaître dans la grille
    }

    /// Crée le scénario comme vraie scène de la pièce sur le bridge.
    public func saveScenario(roomID: String, _ scenario: GalleryScenario) async {
        guard let room = rooms.first(where: { $0.id == roomID }) else { return }
        let actions = SceneGallery.actions(for: scenario, lights: room.lights)
        guard !actions.isEmpty else { return }
        await perform { client in
            try await client.createScene(
                name: scenario.name, groupID: roomID, actions: actions,
                palette: SceneGallery.palette(for: scenario))
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

    // MARK: - Effets (reflet local et arrêt)

    /// Reflet local d'un effet, en v1 ET en v2 (l'UI lit `activeEffect`, v2 en priorité) ;
    /// un effet teinté colore aussi la carte de la lampe.
    private func markEffectLocally(_ effect: String, roomIndex: Int, lightIndex: Int, tint: ColorState? = nil) {
        rooms[roomIndex].lights[lightIndex].effects?.status = effect
        if rooms[roomIndex].lights[lightIndex].effectsV2 != nil {
            if rooms[roomIndex].lights[lightIndex].effectsV2?.status == nil {
                rooms[roomIndex].lights[lightIndex].effectsV2?.status = .init(effect: effect)
            } else {
                rooms[roomIndex].lights[lightIndex].effectsV2?.status?.effect = effect
            }
        }
        if let tint {
            rooms[roomIndex].lights[lightIndex].color = tint
        }
    }

    /// Lampes de la pièce dont un effet tourne (toutes, ou seulement `only`) : les marque
    /// localement comme arrêtées et renvoie leurs ids, à passer à `stopEffects`.
    private func takeActiveEffects(roomIndex: Int, only lightIDs: Set<String>? = nil) -> [String] {
        var running: [String] = []
        for lightIndex in rooms[roomIndex].lights.indices {
            let light = rooms[roomIndex].lights[lightIndex]
            guard light.activeEffect != nil, lightIDs?.contains(light.id) ?? true else { continue }
            running.append(light.id)
            markEffectLocally("no_effect", roomIndex: roomIndex, lightIndex: lightIndex)
        }
        return running
    }

    /// Coupe les effets AVANT d'envoyer un état fixe, dans des PUT à part : le bridge
    /// refuse effet + couleur dans un même PUT, et un effet qui tourne masque la couleur.
    private static func stopEffects(on lightIDs: [String], with client: any HueControlling) async throws {
        for lightID in lightIDs {
            try await client.updateLight(id: lightID, LightUpdate(effects: LightEffects(effect: "no_effect")))
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
