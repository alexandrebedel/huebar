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

@Test func lightUpdateEncodesTemperatureAndEffect() throws {
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

@Test func lightDecodesGradientAndUpdateEncodesPointsOnly() throws {
    let json = """
    {"id":"L9","metadata":{"name":"Strip"},"on":{"on":true},"owner":{"rid":"D9","rtype":"device"},
     "gradient":{"points":[{"color":{"xy":{"x":0.2,"y":0.3}}},{"color":{"xy":{"x":0.5,"y":0.4}}}],
                 "points_capable":5}}
    """
    let light = try JSONDecoder().decode(Light.self, from: Data(json.utf8))
    #expect(light.gradient?.points.count == 2)
    #expect(light.gradient?.pointsCapable == 5)

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let update = LightUpdate(gradient: light.gradient)
    let body = String(data: try encoder.encode(update), encoding: .utf8)!
    // points_capable ne repart jamais en PUT
    #expect(body == #"{"gradient":{"points":[{"color":{"xy":{"x":0.2,"y":0.3}}},{"color":{"xy":{"x":0.5,"y":0.4}}}]}}"#)
}

@MainActor
@Test func setLightGradientIsOptimisticAndSendsPoints() async {
    let fake = FakeClient()
    var strip = colorLight()
    strip.gradient = GradientState(points: [], pointsCapable: 5)
    fake.lights = [strip]
    fake.rooms = [Room(
        id: "R1", metadata: Metadata(name: "Séjour"),
        children: [ref("D1", "device")], services: [ref("G1", "grouped_light")])]
    fake.grouped = [GroupedLight(id: "G1", owner: ref("R1", "room"), on: OnState(on: false), dimming: nil)]
    let state = HueState(client: fake)
    await state.refresh()

    await state.setLightGradient(roomID: "R1", lightID: "L1", colors: [(1, 0, 0), (0, 0, 1)])
    #expect(state.rooms[0].lights[0].gradient?.points.count == 2)
    #expect(state.rooms[0].lights[0].on.on)
    #expect(fake.lightUpdates.last?.update.gradient?.points.count == 2)

    // Une lampe sans gradient ignore l'appel.
    await state.setLightGradient(roomID: "R1", lightID: "absente", colors: [(1, 0, 0)])
    #expect(fake.lightUpdates.count == 1)
}

@Test func sceneDecodesPaletteAndSpeed() throws {
    let json = """
    {"id":"S1","metadata":{"name":"Tokyo"},"group":{"rid":"R1","rtype":"room"},"speed":0.6,
     "palette":{"color":[{"color":{"xy":{"x":0.2,"y":0.3}},"dimming":{"brightness":80}},
                         {"color":{"xy":{"x":0.5,"y":0.4}}}],
                "dimming":[],"color_temperature":[]},
     "status":{"active":"dynamic_palette"}}
    """
    let scene = try JSONDecoder().decode(HueScene.self, from: Data(json.utf8))
    #expect(scene.speed == 0.6)
    #expect(scene.supportsDynamic)
    #expect(scene.isDynamicActive)
    #expect(scene.isActive)

    let plain = HueScene(id: "S2", metadata: Metadata(name: "X"), group: ResourceRef(rid: "R1", rtype: "room"))
    #expect(!plain.supportsDynamic)
    #expect(!plain.isDynamicActive)
}

@MainActor
@Test func recallSceneDynamicAndSpeedReachTheBridge() async {
    let (state, fake) = await makeGalleryState()
    await state.recallSceneDynamic(id: "SC1")
    #expect(fake.dynamicRecalls == ["SC1"])

    await state.setSceneSpeed(id: "SC1", speed: 0.8)
    #expect(fake.sceneSpeeds.map(\.id) == ["SC1"])
    #expect(fake.sceneSpeeds.map(\.speed) == [0.8])
    #expect(state.rooms[0].scenes[0].speed == 0.8) // pas de refresh : la valeur locale reste
}

@MainActor
@Test func saveScenarioIncludesPaletteOnlyForColorScenarios() async throws {
    let (state, fake) = await makeGalleryState()
    let tokyo = try #require(SceneGallery.scenarios.first { $0.name == "Tokyo" })
    await state.saveScenario(roomID: "R1", tokyo)
    #expect(fake.createdScenes[0].palette?.color?.count == 4)

    let white = try #require(SceneGallery.scenarios.first { $0.name == "Lecture" })
    await state.saveScenario(roomID: "R1", white)
    #expect(fake.createdScenes[1].palette == nil)
}

@Test func capturePaletteNeedsTwoColors() {
    var first = colorLight()
    first.on = OnState(on: true)
    first.colorTemperature?.mirek = nil
    var second = colorLight(id: "L2", device: "D2")
    second.on = OnState(on: true)
    second.colorTemperature?.mirek = nil

    let single = SceneCapture.actions(from: [first, whiteLight()])
    #expect(SceneCapture.palette(from: single) == nil)

    let pair = SceneCapture.actions(from: [first, second])
    #expect(SceneCapture.palette(from: pair)?.color?.count == 2)
}

@Test func captureReflectsCurrentLightModes() throws {
    var colorMode = colorLight()
    colorMode.on = OnState(on: true)
    colorMode.colorTemperature?.mirek = nil // mode couleur : le bridge met mirek à null
    var ctMode = whiteLight()
    ctMode.on = OnState(on: true)
    let off = colorLight(id: "L2", device: "D2") // éteinte

    let actions = SceneCapture.actions(from: [colorMode, ctMode, off])
    #expect(actions[0].target == ref("L1", "light"))
    #expect(actions[0].action.color?.xy == XY(x: 0.3, y: 0.3))
    #expect(actions[0].action.colorTemperature == nil)
    #expect(actions[0].action.dimming?.brightness == 50)
    #expect(actions[1].action.colorTemperature?.mirek == 366)
    #expect(actions[1].action.color == nil)
    #expect(actions[2].action.on == OnState(on: false))
    #expect(actions[2].action.dimming == nil)
    #expect(actions[2].action.color == nil)
}

@MainActor
@Test func captureSceneCreatesSceneFromCurrentState() async {
    let (state, fake) = await makeGalleryState()
    await state.captureScene(roomID: "R1", name: "Mon ambiance")
    #expect(fake.createdScenes.count == 1)
    #expect(fake.createdScenes[0].name == "Mon ambiance")
    #expect(fake.createdScenes[0].groupID == "R1")
    #expect(fake.createdScenes[0].actions.count == 3)
}

@MainActor
@Test func setRoomColorTintsColorLightsAndSendsOneGroupedPut() async {
    let (state, fake) = await makeGalleryState()
    await state.setRoomColor(id: "R1", red: 1, green: 0, blue: 0)
    #expect(fake.groupedUpdates.count == 1)
    #expect(fake.groupedUpdates[0].id == "G1")
    #expect(fake.groupedUpdates[0].update.color != nil)
    #expect(fake.groupedUpdates[0].update.on == OnState(on: true))
    // Reflet local : lampes couleur teintées, la blanche (L3) reste sans couleur.
    let expected = HueColor.xy(red: 1, green: 0, blue: 0)
    #expect(state.rooms[0].lights[0].color?.xy == expected)
    #expect(state.rooms[0].lights[2].color == nil)
    let allOn = state.rooms[0].lights.allSatisfy(\.on.on)
    #expect(allOn)
    #expect(state.rooms[0].isOn)
}

@MainActor
@Test func setRoomTemperatureSendsMirekAndUpdatesCTLights() async {
    let (state, fake) = await makeGalleryState()
    await state.setRoomTemperature(id: "R1", mirek: 250)
    #expect(fake.groupedUpdates.count == 1)
    #expect(fake.groupedUpdates[0].update.colorTemperature?.mirek == 250)
    #expect(state.rooms[0].lights[0].colorTemperature?.mirek == 250)
    #expect(state.rooms[0].lights[2].colorTemperature?.mirek == 250)
    #expect(state.rooms[0].isOn)
}

@MainActor
@Test func renamesAreOptimisticAndReachTheBridge() async {
    let (state, fake) = await makeGalleryState()

    await state.renameLight(roomID: "R1", lightID: "L1", name: "Bureau")
    #expect(state.rooms[0].lights[0].metadata.name == "Bureau")

    await state.renameRoom(id: "R1", name: "Salon")
    #expect(state.rooms[0].name == "Salon")

    await state.renameScene(id: "SC1", name: "Soirée")
    #expect(state.rooms[0].scenes[0].metadata.name == "Soirée")

    #expect(fake.renames.map(\.resource) == ["light", "room", "scene"])
    #expect(fake.renames.map(\.name) == ["Bureau", "Salon", "Soirée"])
}

@MainActor
@Test func setLightTemperatureIsOptimisticAndSendsMirek() async {
    let (state, fake) = await makeGalleryState()
    await state.setLightTemperature(roomID: "R1", lightID: "L3", mirek: 250)
    #expect(state.rooms[0].lights[2].colorTemperature?.mirek == 250)
    #expect(state.rooms[0].lights[2].on.on)
    #expect(fake.lightUpdates.last?.update.colorTemperature?.mirek == 250)
}
