import Foundation
@testable import HueKit

final class FakeClient: HueControlling, @unchecked Sendable {
    var lights: [Light] = []
    var rooms: [Room] = []
    var scenes: [HueScene] = []
    var grouped: [GroupedLight] = []
    var shouldFail = false

    private(set) var lightUpdates: [(id: String, update: LightUpdate)] = []
    private(set) var groupedUpdates: [(id: String, update: LightUpdate)] = []
    private(set) var recalledScenes: [String] = []

    private func failIfNeeded() throws {
        if shouldFail { throw HueError.invalidResponse }
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
}
