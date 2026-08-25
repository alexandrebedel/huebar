import Foundation
import Testing
@testable import HueKit

private func ref(_ rid: String, _ rtype: String) -> ResourceRef { ResourceRef(rid: rid, rtype: rtype) }

private func colorLight(id: String = "L1", device: String = "D1") -> Light {
    Light(
        id: id, metadata: Metadata(name: id), on: OnState(on: false),
        dimming: Dimming(brightness: 50), color: ColorState(xy: XY(x: 0.3, y: 0.3)),
        owner: ref(device, "device"),
        colorTemperature: ColorTemperatureState(
            mirek: 300, mirekSchema: MirekSchema(mirekMinimum: 153, mirekMaximum: 454)),
        effects: LightEffects(effectValues: ["no_effect", "candle", "prism"], status: "no_effect")
    )
}

private func whiteLight(id: String = "L3", device: String = "D3") -> Light {
    Light(
        id: id, metadata: Metadata(name: id), on: OnState(on: false),
        dimming: Dimming(brightness: 50), color: nil, owner: ref(device, "device"),
        colorTemperature: ColorTemperatureState(
            mirek: 366, mirekSchema: MirekSchema(mirekMinimum: 153, mirekMaximum: 454))
    )
}

@Test func lightDecodesTemperatureAndEffects() throws {
    let json = """
    {"id":"L1","metadata":{"name":"Go"},"on":{"on":true},"owner":{"rid":"D1","rtype":"device"},
     "color_temperature":{"mirek":366,"mirek_schema":{"mirek_minimum":153,"mirek_maximum":454}},
     "effects":{"effect_values":["no_effect","candle","fire"],"status":"candle"}}
    """
    let light = try JSONDecoder().decode(Light.self, from: Data(json.utf8))
    #expect(light.colorTemperature?.mirek == 366)
    #expect(light.colorTemperature?.mirekSchema == MirekSchema(mirekMinimum: 153, mirekMaximum: 454))
    #expect(light.effects?.effectValues == ["no_effect", "candle", "fire"])
    #expect(light.effects?.status == "candle")
}

@Test func sceneMetadataImageDiscriminatesOfficialScenes() throws {
    let official = """
    {"id":"S1","metadata":{"name":"Honolulu","image":{"rid":"IMG1","rtype":"public_image"}},
     "group":{"rid":"R1","rtype":"room"}}
    """
    let created = #"{"id":"S2","metadata":{"name":"Tokyo"},"group":{"rid":"R1","rtype":"room"}}"#
    let decoder = JSONDecoder()
    let officialScene = try decoder.decode(HueScene.self, from: Data(official.utf8))
    let createdScene = try decoder.decode(HueScene.self, from: Data(created.utf8))
    #expect(officialScene.metadata.image == ResourceRef(rid: "IMG1", rtype: "public_image"))
    #expect(createdScene.metadata.image == nil)
}

@Test func sceneStatusDecodesAndDrivesIsActive() throws {
    let json = """
    {"id":"S1","metadata":{"name":"Repos"},"group":{"rid":"R1","rtype":"room"},
     "status":{"active":"static"}}
    """
    let scene = try JSONDecoder().decode(HueScene.self, from: Data(json.utf8))
    #expect(scene.isActive)
    #expect(HueScene(id: "S2", metadata: Metadata(name: "X"), group: ResourceRef(rid: "R1", rtype: "room")).isActive == false)
}

@MainActor
@Test func refreshCarriesSceneStatusFromBridge() async {
    let (state, fake) = await makeGalleryState()
    #expect(state.rooms[0].scenes[0].isActive == false)
    fake.scenes = [HueScene(
        id: "SC1", metadata: Metadata(name: "Savane"),
        group: ref("R1", "room"), status: SceneStatus(active: "static"))]
    await state.refresh()
    #expect(state.rooms[0].scenes[0].isActive)
}
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys

    let temp = String(data: try encoder.encode(
        LightUpdate(colorTemperature: ColorTemperatureState(mirek: 300))), encoding: .utf8)!
    #expect(temp == #"{"color_temperature":{"mirek":300}}"#)

    let effect = String(data: try encoder.encode(
        LightUpdate(effects: LightEffects(effect: "candle"))), encoding: .utf8)!
    #expect(effect == #"{"effects":{"effect":"candle"}}"#)
}

@Test func galleryPaletteDistributesColorsAndFallsBackToWarmWhite() throws {
    let scenario = try #require(SceneGallery.scenarios.first { $0.name == "Savane" })
    let actions = SceneGallery.actions(
        for: scenario, lights: [colorLight(), colorLight(id: "L2", device: "D2"), whiteLight()])
    #expect(actions.count == 3)
    #expect(actions[0].target == ref("L1", "light"))
    let firstXY = try #require(actions[0].action.color?.xy)
    let secondXY = try #require(actions[1].action.color?.xy)
    #expect(firstXY != secondXY) // palette distribuée, pas la même couleur partout
    #expect(actions[2].action.color == nil)
    #expect(actions[2].action.colorTemperature?.mirek == 370) // lampe sans couleur -> blanc chaud
    let allOn = actions.allSatisfy { $0.action.on == OnState(on: true) }
    #expect(allOn)
}

@Test func galleryWhiteRecipeClampsMirekToLightSchema() throws {
    let scenario = try #require(SceneGallery.scenarios.first { $0.name == "Détente" }) // mirek 447
    let actions = SceneGallery.actions(for: scenario, lights: [whiteLight()])
    #expect(actions[0].action.colorTemperature?.mirek == 447)

    var narrow = whiteLight()
    narrow.colorTemperature?.mirekSchema = MirekSchema(mirekMinimum: 153, mirekMaximum: 400)
    let clamped = SceneGallery.actions(for: scenario, lights: [narrow])
    #expect(clamped[0].action.colorTemperature?.mirek == 400)
}

@MainActor
private func makeGalleryState() async -> (HueState, FakeClient) {
    let fake = FakeClient()
    fake.lights = [colorLight(), colorLight(id: "L2", device: "D2"), whiteLight()]
    fake.rooms = [Room(
        id: "R1", metadata: Metadata(name: "Séjour"),
        children: [ref("D1", "device"), ref("D2", "device"), ref("D3", "device")],
        services: [ref("G1", "grouped_light")])]
    fake.grouped = [GroupedLight(id: "G1", owner: ref("R1", "room"), on: OnState(on: false), dimming: nil)]
    fake.scenes = [HueScene(id: "SC1", metadata: Metadata(name: "Savane"), group: ref("R1", "room"))]
    let state = HueState(client: fake)
    await state.refresh()
    return (state, fake)
}

@MainActor
@Test func deleteSceneRemovesLocallyAndCallsBridge() async {
    let (state, fake) = await makeGalleryState()
    #expect(state.rooms[0].scenes.count == 1)
    await state.deleteScene(id: "SC1")
    #expect(state.rooms[0].scenes.isEmpty)
    #expect(fake.deletedScenes == ["SC1"])
}

@MainActor
@Test func applyScenarioUpdatesLightsLocallyAndSendsOnePutPerLight() async throws {
    let (state, fake) = await makeGalleryState()
    let scenario = try #require(SceneGallery.scenarios.first { $0.name == "Savane" })
    await state.applyScenario(roomID: "R1", scenario)
    #expect(fake.lightUpdates.count == 3)
    let allOn = state.rooms[0].lights.allSatisfy(\.on.on)
    #expect(allOn)
    #expect(state.rooms[0].isOn)
}

@MainActor
@Test func saveScenarioCreatesSceneOnBridge() async throws {
    let (state, fake) = await makeGalleryState()
    let scenario = try #require(SceneGallery.scenarios.first { $0.name == "Tokyo" })
    await state.saveScenario(roomID: "R1", scenario)
    #expect(fake.createdScenes.count == 1)
    #expect(fake.createdScenes[0].name == "Tokyo")
    #expect(fake.createdScenes[0].groupID == "R1")
    #expect(fake.createdScenes[0].actions.count == 3)
}

@MainActor
@Test func setLightTemperatureIsOptimisticAndSendsMirek() async {
    let (state, fake) = await makeGalleryState()
    await state.setLightTemperature(roomID: "R1", lightID: "L3", mirek: 250)
    #expect(state.rooms[0].lights[2].colorTemperature?.mirek == 250)
    #expect(state.rooms[0].lights[2].on.on)
    #expect(fake.lightUpdates.last?.update.colorTemperature?.mirek == 250)
}
