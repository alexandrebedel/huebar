import Foundation
import Testing
@testable import HueKit

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> [T] {
    try JSONDecoder().decode(HueResponse<T>.self, from: Data(json.utf8)).data
}

@Test func decodesLight() throws {
    let json = """
    {"errors":[],"data":[{"id":"L1","type":"light",
      "metadata":{"name":"Hue go 1","archetype":"hue_go"},
      "on":{"on":true},"dimming":{"brightness":35.18,"min_dim_level":2.0},
      "color":{"xy":{"x":0.45,"y":0.40},"gamut_type":"C"},
      "owner":{"rid":"D1","rtype":"device"}}]}
    """
    let lights = try decode(Light.self, json)
    #expect(lights.count == 1)
    #expect(lights[0].id == "L1")
    #expect(lights[0].metadata.name == "Hue go 1")
    #expect(lights[0].on.on == true)
    #expect(lights[0].dimming?.brightness == 35.18)
    #expect(lights[0].color?.xy == XY(x: 0.45, y: 0.40))
    #expect(lights[0].owner.rid == "D1")
}

@Test func decodesLightWithoutColorOrDimming() throws {
    let json = """
    {"errors":[],"data":[{"id":"L2","metadata":{"name":"Basic"},
      "on":{"on":false},"owner":{"rid":"D2","rtype":"device"}}]}
    """
    let lights = try decode(Light.self, json)
    #expect(lights[0].dimming == nil)
    #expect(lights[0].color == nil)
}

@Test func decodesRoom() throws {
    let json = """
    {"errors":[],"data":[{"id":"R1","type":"room",
      "metadata":{"name":"Séjour","archetype":"living_room"},
      "children":[{"rid":"D1","rtype":"device"},{"rid":"D2","rtype":"device"}],
      "services":[{"rid":"G1","rtype":"grouped_light"}]}]}
    """
    let rooms = try decode(Room.self, json)
    #expect(rooms[0].metadata.name == "Séjour")
    #expect(rooms[0].children.map(\.rid) == ["D1", "D2"])
    #expect(rooms[0].services.first(where: { $0.rtype == "grouped_light" })?.rid == "G1")
}

@Test func decodesScene() throws {
    let json = """
    {"errors":[],"data":[{"id":"S1","type":"scene",
      "metadata":{"name":"Repos"},"group":{"rid":"R1","rtype":"room"},
      "status":{"active":"inactive"}}]}
    """
    let scenes = try decode(HueScene.self, json)
    #expect(scenes[0].metadata.name == "Repos")
    #expect(scenes[0].group.rid == "R1")
}

@Test func decodesGroupedLight() throws {
    let json = """
    {"errors":[],"data":[
      {"id":"G1","owner":{"rid":"R1","rtype":"room"},"on":{"on":true},"dimming":{"brightness":35.0}},
      {"id":"GH","owner":{"rid":"BH","rtype":"bridge_home"},"on":{"on":false}}]}
    """
    let grouped = try decode(GroupedLight.self, json)
    #expect(grouped[0].on?.on == true)
    #expect(grouped[1].owner.rtype == "bridge_home")
    #expect(grouped[1].dimming == nil)
}

@Test func encodesLightUpdate() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let onOnly = LightUpdate(on: OnState(on: false))
    #expect(String(data: try encoder.encode(onOnly), encoding: .utf8) == #"{"on":{"on":false}}"#)

    let full = LightUpdate(
        on: OnState(on: true),
        dimming: Dimming(brightness: 50),
        color: ColorState(xy: XY(x: 0.5, y: 0.4))
    )
    #expect(String(data: try encoder.encode(full), encoding: .utf8)
        == #"{"color":{"xy":{"x":0.5,"y":0.4}},"dimming":{"brightness":50},"on":{"on":true}}"#)
}
