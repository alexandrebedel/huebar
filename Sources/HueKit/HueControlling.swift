import Foundation

public protocol HueControlling: Sendable {
    func fetchLights() async throws -> [Light]
    func fetchRooms() async throws -> [Room]
    func fetchScenes() async throws -> [HueScene]
    func fetchGroupedLights() async throws -> [GroupedLight]
    func updateLight(id: String, _ update: LightUpdate) async throws
    func updateGroupedLight(id: String, _ update: LightUpdate) async throws
    func recallScene(id: String) async throws
    func createScene(name: String, groupID: String, actions: [SceneAction]) async throws
}
