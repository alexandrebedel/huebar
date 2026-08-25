import Testing
@testable import HueKit

private func ref(_ rid: String, _ rtype: String) -> ResourceRef {
    ResourceRef(rid: rid, rtype: rtype)
}

private let fixtures = (
    lights: [
        Light(id: "L1", metadata: Metadata(name: "Go 1"), on: OnState(on: true),
              dimming: Dimming(brightness: 35), color: nil, owner: ref("D1", "device")),
        Light(id: "L2", metadata: Metadata(name: "Strip"), on: OnState(on: false),
              dimming: Dimming(brightness: 80), color: nil, owner: ref("D2", "device")),
        Light(id: "L3", metadata: Metadata(name: "Cuisine 1"), on: OnState(on: true),
              dimming: nil, color: nil, owner: ref("D3", "device")),
    ],
    // Séjour d'abord : l'ordre du bridge (celui de l'app Hue) n'est pas alphabétique.
    rooms: [
        Room(id: "R1", metadata: Metadata(name: "Séjour"),
             children: [ref("D1", "device"), ref("D2", "device")],
             services: [ref("G1", "grouped_light")]),
        Room(id: "R2", metadata: Metadata(name: "Cuisine"),
             children: [ref("D3", "device")], services: [ref("G2", "grouped_light")]),
    ],
    scenes: [
        HueScene(id: "S1", metadata: Metadata(name: "Repos"), group: ref("R1", "room")),
        HueScene(id: "S2", metadata: Metadata(name: "Soho"), group: ref("R1", "room")),
        HueScene(id: "S3", metadata: Metadata(name: "Lumineux"), group: ref("R2", "room")),
        HueScene(id: "S4", metadata: Metadata(name: "Veilleuse"), group: ref("BH", "bridge_home")),
    ],
    grouped: [
        GroupedLight(id: "G1", owner: ref("R1", "room"), on: OnState(on: true), dimming: Dimming(brightness: 35)),
        GroupedLight(id: "G2", owner: ref("R2", "room"), on: OnState(on: false), dimming: nil),
        GroupedLight(id: "GH", owner: ref("BH", "bridge_home"), on: OnState(on: true), dimming: nil),
    ]
)

@Test func buildsRoomsInBridgeOrder() throws {
    let built = HueState.makeRooms(
        lights: fixtures.lights, rooms: fixtures.rooms,
        scenes: fixtures.scenes, grouped: fixtures.grouped
    )
    #expect(built.rooms.map(\.name) == ["Séjour", "Cuisine"])

    let sejour = try #require(built.rooms.first)
    #expect(sejour.groupedLightID == "G1")
    #expect(sejour.isOn == true)
    #expect(sejour.brightness == 35)
    #expect(sejour.lights.map(\.id) == ["L1", "L2"])
    #expect(sejour.scenes.map(\.id) == ["S1", "S2"])

    let cuisine = try #require(built.rooms.last)
    #expect(cuisine.isOn == false)
    #expect(cuisine.brightness == 100) // pas de dimming -> défaut
    #expect(cuisine.lights.map(\.id) == ["L3"])
}

@Test func buildsBridgeHomeZone() throws {
    let built = HueState.makeRooms(
        lights: fixtures.lights, rooms: fixtures.rooms,
        scenes: fixtures.scenes, grouped: fixtures.grouped
    )
    let all = try #require(built.all)
    #expect(all.groupedLightID == "GH")
    #expect(all.isOn == true)
    #expect(all.scenes.map(\.id) == ["S4"])
}

@Test func missingGroupedLightYieldsNilAll() {
    let built = HueState.makeRooms(lights: [], rooms: [], scenes: [], grouped: [])
    #expect(built.all == nil)
    #expect(built.rooms.isEmpty)
}
