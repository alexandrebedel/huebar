import Foundation
@testable import HueKit

final class FakeClient: HueControlling, @unchecked Sendable {
    var lights: [Light] = []
    var rooms: [Room] = []
    var scenes: [HueScene] = []
    var grouped: [GroupedLight] = []
    var shouldFail = false
    /// Fait échouer les N prochains appels (simule le premier hit à froid) — thread-safe,
    /// refresh() lance ses 4 fetches en parallèle.
    var failuresRemaining: Int {
        get { failuresLock.withLock { _failuresRemaining } }
        set { failuresLock.withLock { _failuresRemaining = newValue } }
    }
    private let failuresLock = NSLock()
    private var _failuresRemaining = 0

    private(set) var lightUpdates: [(id: String, update: LightUpdate)] = []
    private(set) var groupedUpdates: [(id: String, update: LightUpdate)] = []
    private(set) var recalledScenes: [String] = []
    private(set) var dynamicRecalls: [String] = []
    private(set) var sceneSpeeds: [(id: String, speed: Double)] = []
    private(set) var createdScenes: [(name: String, groupID: String, actions: [SceneAction], palette: ScenePalette?)] = []
    private(set) var deletedScenes: [String] = []
    private(set) var renames: [(resource: String, id: String, name: String)] = []

    private func failIfNeeded() throws {
        if shouldFail { throw HueError.invalidResponse }
        let mustFail = failuresLock.withLock {
            guard _failuresRemaining > 0 else { return false }
            _failuresRemaining -= 1
            return true
        }
        if mustFail { throw HueError.invalidResponse }
    }

    func createScene(name: String, groupID: String, actions: [SceneAction], palette: ScenePalette?) async throws {
        try failIfNeeded()
        createdScenes.append((name: name, groupID: groupID, actions: actions, palette: palette))
    }

    func recallDynamicScene(id: String) async throws {
        try failIfNeeded()
        dynamicRecalls.append(id)
    }

    func setSceneSpeed(id: String, speed: Double) async throws {
        try failIfNeeded()
        sceneSpeeds.append((id, speed))
    }

    func deleteScene(id: String) async throws {
        try failIfNeeded()
        deletedScenes.append(id)
    }

    func fetchLights() async throws -> [Light] { try failIfNeeded(); return lights }
    func fetchRooms() async throws -> [Room] { try failIfNeeded(); return rooms }
    func fetchScenes() async throws -> [HueScene] { try failIfNeeded(); return scenes }
    func fetchGroupedLights() async throws -> [GroupedLight] { try failIfNeeded(); return grouped }

    func updateLight(id: String, _ update: LightUpdate) async throws {
        try failIfNeeded()
        lightUpdates.append((id, update))
    }

    func updateGroupedLight(id: String, _ update: LightUpdate) async throws {
        try failIfNeeded()
        groupedUpdates.append((id, update))
    }

    func recallScene(id: String) async throws {
        try failIfNeeded()
        recalledScenes.append(id)
    }

    func renameLight(id: String, name: String) async throws {
        try failIfNeeded()
        renames.append(("light", id, name))
    }

    func renameRoom(id: String, name: String) async throws {
        try failIfNeeded()
        renames.append(("room", id, name))
    }

    func renameScene(id: String, name: String) async throws {
        try failIfNeeded()
        renames.append(("scene", id, name))
    }
}
