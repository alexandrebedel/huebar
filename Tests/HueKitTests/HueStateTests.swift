import Testing
@testable import HueKit

@MainActor
private func makeReadyState() async -> (HueState, FakeClient) {
    let fake = FakeClient()
    let ref = { (rid: String, rtype: String) in ResourceRef(rid: rid, rtype: rtype) }
    fake.lights = [
        Light(id: "L1", metadata: Metadata(name: "Go 1"), on: OnState(on: false),
              dimming: Dimming(brightness: 40), color: nil, owner: ref("D1", "device"))
    ]
    fake.rooms = [
        Room(id: "R1", metadata: Metadata(name: "Séjour"),
             children: [ref("D1", "device")], services: [ref("G1", "grouped_light")])
    ]
    fake.scenes = [HueScene(id: "S1", metadata: Metadata(name: "Repos"), group: ref("R1", "room"))]
    fake.grouped = [
        GroupedLight(id: "G1", owner: ref("R1", "room"), on: OnState(on: false), dimming: Dimming(brightness: 40)),
        GroupedLight(id: "GH", owner: ref("BH", "bridge_home"), on: OnState(on: false), dimming: nil),
    ]
    let state = HueState(client: fake)
    state.recallSettleDelay = .zero // pas d'attente de fade dans les tests
    await state.refresh()
    return (state, fake)
}

@MainActor
@Test func refreshBuildsStateAndBecomesReady() async {
    let (state, _) = await makeReadyState()
    #expect(state.status == .ready)
    #expect(state.rooms.count == 1)
    #expect(state.all?.groupedLightID == "GH")
}

@MainActor
@Test func refreshFailureSetsError() async {
    let fake = FakeClient()
    fake.shouldFail = true
    let state = HueState(client: fake)
    await state.refresh()
    #expect(state.status == .error("Bridge injoignable"))
}

@MainActor
@Test func missingClientReportsConfigError() async {
    let state = HueState(client: nil, errorMessage: "Credentials introuvables")
    await state.refresh()
    #expect(state.status == .error("Credentials introuvables"))
}

@MainActor
@Test func toggleRoomIsOptimisticAndCallsGroupedLight() async {
    let (state, fake) = await makeReadyState()
    await state.toggleRoom(id: "R1")
    #expect(state.rooms[0].isOn == true)
    #expect(fake.groupedUpdates.count == 1)
    #expect(fake.groupedUpdates[0].id == "G1")
    #expect(fake.groupedUpdates[0].update.on == OnState(on: true))
}

@MainActor
@Test func toggleAllTogglesBridgeHomeGroup() async {
    let (state, fake) = await makeReadyState()
    await state.toggleAll()
    #expect(state.all?.isOn == true)
    #expect(fake.groupedUpdates.map(\.id) == ["GH"])
}

@MainActor
@Test func refreshRetriesSilentlyAfterColdStartFailure() async {
    // Premier hit à froid (ARP/TLS/Wi-Fi en veille) : les 4 fetches échouent une fois,
    // le retry silencieux doit aboutir sans jamais montrer « Bridge injoignable ».
    let (state, fake) = await makeReadyState()
    fake.failuresRemaining = 4
    await state.refresh()
    #expect(state.status == .ready)
}

@MainActor
@Test func setRoomBrightnessSendsDimming() async {
    let (state, fake) = await makeReadyState()
    await state.setRoomBrightness(id: "R1", 70)
    #expect(state.rooms[0].brightness == 70)
    #expect(fake.groupedUpdates[0].update.dimming == Dimming(brightness: 70))
}

@MainActor
@Test func setRoomBrightnessPropagatesToLightsLocally() async {
    // Le PUT grouped_light allume et dimme toutes les lampes : l'état local doit suivre
    // immédiatement (sliders des lampes + moyenne du slider de pièce), sans refresh.
    let (state, fake) = await makeReadyState()
    #expect(state.rooms[0].lights[0].on.on == false)
    await state.setRoomBrightness(id: "R1", 70)
    #expect(state.rooms[0].lights[0].on.on == true)
    #expect(state.rooms[0].lights[0].dimming == Dimming(brightness: 70))
    #expect(fake.lightUpdates.isEmpty) // un seul PUT grouped, pas un par lampe
}

@MainActor
@Test func toggleLightUpdatesLightLocally() async {
    let (state, fake) = await makeReadyState()
    await state.toggleLight(roomID: "R1", lightID: "L1")
    #expect(state.rooms[0].lights[0].on.on == true)
    #expect(fake.lightUpdates.map(\.id) == ["L1"])
}

@MainActor
@Test func setLightColorSendsXY() async {
    let (state, fake) = await makeReadyState()
    await state.setLightColor(roomID: "R1", lightID: "L1", red: 1, green: 0, blue: 0)
    let update = fake.lightUpdates[0].update
    #expect(abs((update.color?.xy.x ?? 0) - 0.7006) < 0.01)
    #expect(update.on == OnState(on: true)) // choisir une couleur allume la lampe
}

@MainActor
@Test func recallSceneCallsClientThenRefreshes() async {
    let (state, fake) = await makeReadyState()
    fake.grouped[0].on = OnState(on: true) // le refresh doit ramasser le nouvel état
    await state.recallScene(id: "S1")
    #expect(fake.recalledScenes == ["S1"])
    #expect(state.rooms[0].isOn == true)
}

@MainActor
@Test func failedActionEndsInErrorStatus() async {
    let (state, fake) = await makeReadyState()
    fake.shouldFail = true
    await state.toggleRoom(id: "R1")
    #expect(state.status == .error("Bridge injoignable"))
}
