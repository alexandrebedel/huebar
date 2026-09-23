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
    state.recallSettleDelay = .zero // pas d'attente de fade dans les tests
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
@Test func recallPaintsSceneEndStateLocallyDuringTheFade() async {
    // Résidus constatés en réel : le refresh immédiat tombait pendant le fade du
    // bridge et figeait des couleurs de l'ancienne scène. On peint l'état FINAL
    // localement dès le clic.
    let (state, _) = await makeGalleryState()
    let targetXY = XY(x: 0.2, y: 0.7)
    var scene = state.rooms[0].scenes[0]
    scene.actions = [
        SceneAction(action: .init(on: OnState(on: true), dimming: Dimming(brightness: 90),
                                  color: ColorState(xy: targetXY)),
                    target: ref("L1", "light")),
        SceneAction(action: .init(on: OnState(on: true),
                                  colorTemperature: ColorTemperatureState(mirek: 250)),
                    target: ref("L3", "light")),
        SceneAction(action: .init(on: OnState(on: false)), target: ref("L2", "light")),
    ]
    state.rooms[0].scenes[0] = scene

    state.applySceneActionsLocally(id: "SC1")
    #expect(state.rooms[0].lights[0].color?.xy == targetXY)
    #expect(state.rooms[0].lights[0].colorTemperature?.mirek == nil) // passée en mode couleur
    #expect(state.rooms[0].lights[0].dimming?.brightness == 90)
    #expect(state.rooms[0].lights[0].on.on)
    #expect(state.rooms[0].lights[1].on.on == false)
    #expect(state.rooms[0].lights[2].colorTemperature?.mirek == 250)
    #expect(state.rooms[0].isOn) // au moins une lampe allumée
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

@Test func campfireScenarioUsesNativeFireWithCandleFallback() throws {
    let campfire = try #require(SceneGallery.scenarios.first { $0.name == "Feu de camp" })
    #expect(campfire.isAnimated)
    var candleOnly = colorLight(id: "L2", device: "D2")
    candleOnly.effects = LightEffects(effectValues: ["no_effect", "candle"], status: "no_effect")
    var fireCapable = colorLight()
    fireCapable.effects = LightEffects(effectValues: ["no_effect", "candle", "fire"], status: "no_effect")

    let actions = SceneGallery.actions(for: campfire, lights: [fireCapable, candleOnly, whiteLight()])
    #expect(actions[0].action.effects?.effect == "fire")
    #expect(actions[1].action.effects?.effect == "candle") // pas de fire : repli bougie
    #expect(actions[2].action.effects == nil)               // lampe sans effets : état fixe
    #expect(actions[2].action.colorTemperature != nil)
    // Vérifié sur le vrai bridge : « effects.effect cannot be combined with color » (HTTP 400).
    #expect(actions[0].action.color == nil)
    #expect(actions[1].action.color == nil)

    // Le PUT direct (« Appliquer ») et l'encodage de scène portent bien l'effet.
    #expect(LightUpdate(applying: actions[0].action).effects?.effect == "fire")
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = String(data: try encoder.encode(actions[0].action), encoding: .utf8) ?? ""
    #expect(json.contains(#""effects":{"effect":"fire"}"#))
}

@MainActor
@Test func setRoomEffectFansOutToSupportingLightsOnly() async {
    let (state, fake) = await makeGalleryState()
    // L1 et L2 supportent candle/prism (fixture), L3 (blanche) n'a pas d'effets.
    await state.setRoomEffect(id: "R1", effect: "candle")
    #expect(fake.lightUpdates.map(\.id) == ["L1", "L2"])
    #expect(fake.lightUpdates.allSatisfy { $0.update.effects?.effect == "candle" })
    #expect(state.rooms[0].lights[0].effects?.status == "candle")
    #expect(state.rooms[0].lights[0].on.on)
    #expect(state.rooms[0].isOn)

    // Effet non supporté par aucune lampe : rien n'est envoyé.
    await state.setRoomEffect(id: "R1", effect: "fire")
    #expect(fake.lightUpdates.count == 2)
}

@Test func captureKeepsActiveNativeEffect() {
    var candle = colorLight()
    candle.on = OnState(on: true)
    candle.effects?.status = "candle"
    let actions = SceneCapture.actions(from: [candle])
    #expect(actions[0].action.effects?.effect == "candle")
    #expect(actions[0].action.color == nil)             // effet OU couleur, jamais les deux
    #expect(actions[0].action.colorTemperature == nil)
    #expect(SceneCapture.palette(from: actions) == nil) // scène déjà animée : pas de palette
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

// MARK: - Effets v2 (teintés) et scènes « film d'horreur »

private let allEffects = ["no_effect", "candle", "fire", "prism", "sparkle", "opal", "glisten"]

/// Lampe couleur dont le firmware expose `effects_v2` (forme relevée sur le vrai bridge).
private func v2Light(id: String = "L1", device: String = "D1", running effect: String = "no_effect") -> Light {
    var light = colorLight(id: id, device: device)
    light.effects = LightEffects(effectValues: allEffects, status: effect)
    light.effectsV2 = LightEffectsV2(
        action: .init(effect: nil, effectValues: allEffects),
        status: .init(effect: effect, effectValues: allEffects))
    return light
}

@Test func lightDecodesEffectsV2AsServedByTheBridge() throws {
    let json = """
    {"id":"L1","metadata":{"name":"Hue go 1"},"on":{"on":true},"owner":{"rid":"D1","rtype":"device"},
     "effects":{"effect_values":["no_effect","candle","fire"],"status":"candle","status_values":["no_effect","candle"]},
     "effects_v2":{"action":{"effect_values":["no_effect","candle","fire"]},
                   "status":{"effect":"candle","effect_values":["no_effect","candle","fire"],
                             "parameters":{"color":{"xy":{"x":0.6915,"y":0.3083}},
                                           "color_temperature":{"mirek":null,"mirek_valid":false},"speed":0.3}}}}
    """
    let light = try JSONDecoder().decode(Light.self, from: Data(json.utf8))
    #expect(light.effectsV2?.supportedEffects == ["no_effect", "candle", "fire"])
    #expect(light.effectsV2?.status?.parameters?.color?.xy == XY(x: 0.6915, y: 0.3083))
    #expect(light.effectsV2?.status?.parameters?.speed == 0.3)
    #expect(light.activeEffect == "candle")
    #expect(v2Light().activeEffect == nil) // « no_effect » n'est pas un effet en cours
}

@Test func horrorScenarioTintsTheCandleThroughEffectsV2() throws {
    let horror = try #require(SceneGallery.scenarios.first { $0.name == "Film d'horreur" })
    #expect(horror.category == .horror)
    // L1 sait teinter ses effets (v2) ; L2 n'a que l'ancien `effects` (bougie orange imposée).
    let actions = SceneGallery.actions(for: horror, lights: [v2Light(), colorLight(id: "L2", device: "D2")])

    let tinted = try #require(actions[0].action.effectsV2?.action)
    #expect(tinted.effect == "candle")
    #expect(tinted.parameters?.color == ColorState(xy: HueColor.xy(red: 1, green: 0.05, blue: 0.02)))
    #expect(tinted.parameters?.speed == 0.5) // réglé en réel : 0.25 invisible, 0.8 trop rapide
    #expect(actions[0].action.color == nil)   // la couleur vit DANS l'effet
    #expect(actions[0].action.effects == nil)
    #expect(actions[0].action.dimming?.brightness == 14)

    // Sans v2, une bougie serait orange : le rouge sang prime, donc couleur fixe sans effet.
    #expect(actions[1].action.effectName == nil)
    #expect(actions[1].action.color != nil)
}

@Test func noGalleryActionEverCombinesAnEffectWithAColor() {
    // Règle du bridge (HTTP 400 sinon) — verrouillée pour TOUS les scénarios et types de lampes.
    let lights = [v2Light(), colorLight(id: "L2", device: "D2"), whiteLight()]
    for scenario in SceneGallery.scenarios {
        for action in SceneGallery.actions(for: scenario, lights: lights) {
            let body = action.action
            if body.effectName != nil {
                #expect(body.color == nil, "\(scenario.name)")
                #expect(body.colorTemperature == nil, "\(scenario.name)")
            }
            #expect(!(body.effects != nil && body.effectsV2 != nil), "\(scenario.name)")
        }
    }
}

@Test func tintedEffectUpdateEncodesOnlyTheCommand() throws {
    let horror = try #require(SceneGallery.scenarios.first { $0.name == "Film d'horreur" })
    let body = SceneGallery.actions(for: horror, lights: [v2Light()])[0].action
    let data = try JSONEncoder().encode(LightUpdate(applying: body))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["on", "dimming", "effects_v2"]) // surtout pas de `color` au 1er niveau
    let command = try #require((object["effects_v2"] as? [String: Any])?["action"] as? [String: Any])
    #expect(Set(command.keys) == ["effect", "parameters"])      // ni status ni effect_values
    // Même forme pour l'action de scène (POST /scene), validée telle quelle par le bridge.
    let scene = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as? [String: Any])
    #expect(Set(scene.keys) == ["on", "dimming", "effects_v2"])
}

@Test func horrorScenesStayDimAndAnimatedOnesCarryNoPalette() throws {
    let horrors = SceneGallery.scenarios.filter { $0.category == .horror }
    #expect(horrors.count >= 4)
    #expect(horrors.allSatisfy { $0.brightness <= 35 }) // pour regarder un film, pas pour lire
    for scenario in SceneGallery.scenarios where scenario.isAnimated {
        #expect(SceneGallery.palette(for: scenario) == nil, "\(scenario.name)")
    }
    let giallo = try #require(SceneGallery.scenarios.first { $0.name == "Giallo" })
    #expect(SceneGallery.palette(for: giallo)?.color?.count == 4) // fixe : dynamisable
}

@Test func captureKeepsATintedEffectWithItsColor() {
    var light = v2Light(running: "candle")
    light.on = OnState(on: true)
    let red = ColorState(xy: XY(x: 0.6915, y: 0.3083))
    light.effectsV2?.status?.parameters = .init(
        color: red, colorTemperature: .init(mirek: nil, mirekValid: false), speed: 0.25)
    let body = SceneCapture.actions(from: [light])[0].action
    #expect(body.effectsV2?.action?.effect == "candle")
    #expect(body.effectsV2?.action?.parameters?.color == red)
    #expect(body.effectsV2?.action?.parameters?.colorTemperature == nil) // mirek invalide : ignoré
    #expect(body.effectsV2?.action?.parameters?.speed == 0.25)
    #expect(body.color == nil)
    #expect(body.effects == nil)
}

@Test func sceneCardsShowEffectColors() {
    let red = ColorState(xy: HueColor.xy(red: 1, green: 0.05, blue: 0.02))
    let scene = HueScene(
        id: "S1", metadata: Metadata(name: "Film d'horreur"), group: ref("R1", "room"),
        actions: [
            SceneAction(action: .init(on: OnState(on: true), effectsV2: LightEffectsV2(effect: "candle", color: red))),
            SceneAction(action: .init(on: OnState(on: true), effects: LightEffects(effect: "fire"))),
        ])
    let stops = SceneGradient.stops(for: scene)
    #expect(stops.count == 2)
    #expect(stops[0].red > 0.9 && stops[0].green < 0.35) // la teinte de l'effet, pas un blanc chaud par défaut
    #expect(stops[1] == SceneGradient.naturalEffectColors["fire"])
    #expect(SceneGradient.hueAnchors(for: scene).count == 2)  // utilisable comme thème de sync
}

@MainActor
private func makeEffectState(running effect: String) async -> (HueState, FakeClient) {
    let fake = FakeClient()
    fake.lights = [v2Light(running: effect), v2Light(id: "L2", device: "D2")]
    for index in fake.lights.indices { fake.lights[index].on = OnState(on: true) }
    fake.rooms = [Room(
        id: "R1", metadata: Metadata(name: "Séjour"),
        children: [ref("D1", "device"), ref("D2", "device")], services: [ref("G1", "grouped_light")])]
    fake.grouped = [GroupedLight(id: "G1", owner: ref("R1", "room"), on: OnState(on: true), dimming: nil)]
    let state = HueState(client: fake)
    state.recallSettleDelay = .zero
    await state.refresh()
    return (state, fake)
}

@MainActor
@Test func aStaticScenarioStopsRunningEffectsInASeparatePut() async throws {
    // L1 joue une bougie ; « Clair de lune » est fixe : l'effet est coupé d'abord, SEUL dans
    // son PUT (effet + couleur dans un même PUT = 400), puis la couleur part.
    let (state, fake) = await makeEffectState(running: "candle")
    let moonlight = try #require(SceneGallery.scenarios.first { $0.name == "Clair de lune" })
    await state.applyScenario(roomID: "R1", moonlight)

    let first = try #require(fake.lightUpdates.first)
    #expect(first.id == "L1")
    #expect(first.update.effects?.effect == "no_effect")
    #expect(first.update.color == nil)
    #expect(fake.lightUpdates.count == 3) // stop L1, puis une couleur par lampe
    #expect(fake.lightUpdates.dropFirst().allSatisfy { $0.update.color != nil && $0.update.effects == nil })
    #expect(state.rooms[0].lights[0].activeEffect == nil)
}

@MainActor
@Test func applyingATintedScenarioMarksTheEffectAndTintsTheCard() async throws {
    let (state, fake) = await makeEffectState(running: "no_effect")
    let horror = try #require(SceneGallery.scenarios.first { $0.name == "Film d'horreur" })
    await state.applyScenario(roomID: "R1", horror)

    #expect(fake.lightUpdates.count == 2) // aucun effet à couper : un PUT par lampe
    #expect(fake.lightUpdates.allSatisfy { $0.update.effectsV2?.action?.effect == "candle" && $0.update.color == nil })
    #expect(state.rooms[0].lights[0].activeEffect == "candle")
    #expect(state.rooms[0].lights[0].color == ColorState(xy: HueColor.xy(red: 1, green: 0.05, blue: 0.02)))
    #expect(state.rooms[0].lights[0].dimming?.brightness == 14)
}

@MainActor
@Test func pickingAColorStopsTheRunningEffectFirst() async {
    let (state, fake) = await makeEffectState(running: "fire")
    await state.setLightColor(roomID: "R1", lightID: "L1", red: 0, green: 0, blue: 1)
    #expect(fake.lightUpdates.count == 2)
    #expect(fake.lightUpdates[0].update.effects?.effect == "no_effect")
    #expect(fake.lightUpdates[1].update.color != nil)

    // Pièce entière : seules les lampes animées reçoivent le stop, puis un seul PUT groupé.
    let (roomState, roomFake) = await makeEffectState(running: "candle")
    await roomState.setRoomColor(id: "R1", red: 1, green: 0, blue: 0)
    #expect(roomFake.lightUpdates.map(\.id) == ["L1"])
    #expect(roomFake.groupedUpdates.count == 1)
}

@MainActor
@Test func recallingAStaticSceneStopsEffectsItFreezes() async {
    let (state, fake) = await makeEffectState(running: "candle")
    var scene = HueScene(id: "SC9", metadata: Metadata(name: "Repos"), group: ref("R1", "room"))
    scene.actions = [
        SceneAction(action: .init(on: OnState(on: true), color: ColorState(xy: XY(x: 0.5, y: 0.4))),
                    target: ref("L1", "light")),
        SceneAction(action: .init(on: OnState(on: true), effects: LightEffects(effect: "fire")),
                    target: ref("L2", "light")),
    ]
    state.rooms[0].scenes = [scene]

    let toStop = state.applySceneActionsLocally(id: "SC9")
    #expect(toStop == ["L1"])                                  // L2 reçoit un nouvel effet : rien à couper
    #expect(state.rooms[0].lights[0].activeEffect == nil)
    #expect(state.rooms[0].lights[1].activeEffect == "fire")
    _ = fake
}

// MARK: - Réglage de l'effet d'une scène (type, vitesse, luminosité)

private func horrorScene(lights: [Light]) throws -> HueScene {
    let horror = try #require(SceneGallery.scenarios.first { $0.name == "Film d'horreur" })
    return HueScene(
        id: "SC7", metadata: Metadata(name: "Film d'horreur"), group: ref("R1", "room"),
        actions: SceneGallery.actions(for: horror, lights: lights))
}

@Test func effectSettingsReadTheSceneAndRewriteEveryAnimatedLamp() throws {
    let scene = try horrorScene(lights: [v2Light(), v2Light(id: "L2", device: "D2")])
    #expect(SceneEffectSettings(scene: scene) == SceneEffectSettings(effect: "candle", speed: 0.5, brightness: 14))
    #expect(SceneEffectSettings.hasSpeed(scene))

    let actions = scene.actions ?? []
    let tuned = SceneEffectSettings(effect: "fire", speed: 0.4, brightness: 20).applied(to: actions)
    #expect(tuned.count == 2)
    for (before, after) in zip(actions, tuned) {
        let command = try #require(after.action.effectsV2?.action)
        #expect(command.effect == "fire")
        #expect(command.parameters?.speed == 0.4)
        #expect(command.parameters?.color == before.action.effectsV2?.action?.parameters?.color) // teinte gardée
        #expect(after.action.dimming?.brightness == 20)
        #expect(after.action.color == nil) // jamais de couleur à côté d'un effet
        #expect(after.target == before.target)
    }
    // Une scène fixe n'a rien à régler.
    #expect(SceneEffectSettings(scene: HueScene(id: "S", metadata: Metadata(name: "X"), group: ref("R1", "room"))) == nil)
}

@Test func effectSettingsLeaveFixedLampsAloneAndGiveV1EffectsNoSpeed() {
    let actions = [
        SceneAction(action: .init(on: OnState(on: true), dimming: Dimming(brightness: 60),
                                  effects: LightEffects(effect: "fire")), target: ref("L1", "light")),
        SceneAction(action: .init(on: OnState(on: true), dimming: Dimming(brightness: 60),
                                  color: ColorState(xy: XY(x: 0.5, y: 0.4))), target: ref("L2", "light")),
        SceneAction(action: .init(on: OnState(on: false)), target: ref("L3", "light")),
    ]
    let scene = HueScene(id: "S", metadata: Metadata(name: "Feu de camp"), group: ref("R1", "room"), actions: actions)
    #expect(!SceneEffectSettings.hasSpeed(scene)) // l'ancien `effects` n'a pas de vitesse

    let tuned = SceneEffectSettings(effect: "candle", speed: 0.9, brightness: 30).applied(to: actions)
    #expect(tuned[0].action.effects == LightEffects(effect: "candle"))
    #expect(tuned[0].action.effectsV2 == nil)
    #expect(tuned[1].action.color == actions[1].action.color) // lampe fixe : même couleur…
    #expect(tuned[1].action.effectName == nil)
    #expect(tuned[1].action.dimming?.brightness == 30)         // …à la luminosité de la scène
    #expect(tuned[2] == actions[2])                            // lampe éteinte : intacte
}

@Test func onlyEffectsEveryAnimatedLampCanPlayAreOffered() throws {
    // Le lightstrip sait jouer « underwater », pas le Hue go : le bridge refuserait la scène.
    var strip = v2Light(id: "L2", device: "D2")
    let stripEffects = allEffects + ["underwater", "cosmos"]
    strip.effectsV2 = LightEffectsV2(
        action: .init(effect: nil, effectValues: stripEffects),
        status: .init(effect: "no_effect", effectValues: stripEffects))
    let scene = try horrorScene(lights: [v2Light(), strip])
    #expect(SceneEffectSettings.availableEffects(for: scene, lights: [v2Light(), strip])
            == ["candle", "fire", "prism", "sparkle", "opal", "glisten"])
}

@MainActor
@Test func tuningASceneEffectRewritesItsActionsThenReplaysIt() async throws {
    let (state, fake) = await makeEffectState(running: "no_effect")
    state.rooms[0].scenes = [try horrorScene(lights: state.rooms[0].lights)]

    await state.updateSceneEffect(id: "SC7", SceneEffectSettings(effect: "fire", speed: 0.4, brightness: 20))

    #expect(fake.sceneCalls == ["actions:SC7", "recall:SC7"]) // réécrite AVANT d'être rejouée
    let sent = try #require(fake.sceneActionUpdates.first?.actions)
    #expect(sent.count == 2) // toutes les lampes de la pièce, sinon 400
    #expect(sent.allSatisfy { $0.action.effectsV2?.action?.effect == "fire" })
    #expect(state.rooms[0].scenes[0].actions == sent) // le modèle suit : le réglage se rouvre à jour
    #expect(state.rooms[0].scenes[0].isActive)
    #expect(state.rooms[0].lights.allSatisfy { $0.activeEffect == "fire" && $0.dimming?.brightness == 20 })
}
