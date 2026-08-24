import Foundation
import Testing
@testable import HueKit

/// Tests contre le vrai bridge — exécutés uniquement avec HUE_INTEGRATION=1.
/// `realBridgeLightRoundTrip` fait clignoter une lampe puis restaure son état.
private let integrationEnabled = ProcessInfo.processInfo.environment["HUE_INTEGRATION"] == "1"

@Suite(.serialized)
struct IntegrationTests {
    @Test(.enabled(if: integrationEnabled))
    func realBridgeFetchAndMapping() async throws {
        let client = HueClient(config: try HueConfig.load())
        async let lights = client.fetchLights()
        async let rooms = client.fetchRooms()
        async let scenes = client.fetchScenes()
        async let grouped = client.fetchGroupedLights()
        let built = HueState.makeRooms(
            lights: try await lights, rooms: try await rooms,
            scenes: try await scenes, grouped: try await grouped
        )
        #expect(!built.rooms.isEmpty)
        #expect(built.all != nil)
        #expect(built.rooms.allSatisfy { !$0.lights.isEmpty })
    }

    @Test(.enabled(if: integrationEnabled))
    func realBridgeLightRoundTrip() async throws {
        let client = HueClient(config: try HueConfig.load())
        let lights = try await client.fetchLights()
        let target = try #require(lights.first)
        let initial = target.on.on

        try await client.updateLight(id: target.id, LightUpdate(on: OnState(on: !initial)))
        try await Task.sleep(for: .milliseconds(800))
        var refreshed = try await client.fetchLights()
        #expect(refreshed.first { $0.id == target.id }?.on.on == !initial)

        try await client.updateLight(id: target.id, LightUpdate(on: OnState(on: initial)))
        try await Task.sleep(for: .milliseconds(800))
        refreshed = try await client.fetchLights()
        #expect(refreshed.first { $0.id == target.id }?.on.on == initial)
    }
}
