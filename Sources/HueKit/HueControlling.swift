import Foundation

public protocol HueControlling: Sendable {
    func fetchLights() async throws -> [Light]
    func fetchRooms() async throws -> [Room]
    func fetchScenes() async throws -> [HueScene]
    func fetchGroupedLights() async throws -> [GroupedLight]
    func updateLight(id: String, _ update: LightUpdate) async throws
    func updateGroupedLight(id: String, _ update: LightUpdate) async throws
    func recallScene(id: String) async throws
    func recallDynamicScene(id: String) async throws
    func setSceneSpeed(id: String, speed: Double) async throws
    func createScene(name: String, groupID: String, actions: [SceneAction], palette: ScenePalette?) async throws
    func updateSceneActions(id: String, actions: [SceneAction]) async throws
    func deleteScene(id: String) async throws
    func renameLight(id: String, name: String) async throws
    func renameRoom(id: String, name: String) async throws
    func renameScene(id: String, name: String) async throws
}
