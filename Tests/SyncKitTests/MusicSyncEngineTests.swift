import Foundation
import Testing
@testable import HueKit
@testable import SyncKit
@testable import WaveKit

// MARK: - Fakes

private final class FakeEntertainment: EntertainmentControlling, @unchecked Sendable {
    var configs = [EntertainmentConfig(
        id: "bce767fc-ddba-4747-bec1-2313f5dfbbac",
        metadata: Metadata(name: "HueBar Sync"),
        status: "inactive",
        channels: [
            .init(channelID: 0, position: .init(x: -1, y: 1, z: 0)),
            .init(channelID: 1, position: .init(x: 1, y: 1, z: 0)),
        ])]
    private(set) var started: [String] = []
    private(set) var stopped: [String] = []
    private(set) var applicationIDFetches = 0
    var failFetches = false

    func fetchEntertainmentConfigurations() async throws -> [EntertainmentConfig] {
        if failFetches { throw HueError.invalidResponse }
        return configs
    }
    func startEntertainment(id: String) async throws { started.append(id) }
    func stopEntertainment(id: String) async throws { stopped.append(id) }
    func fetchApplicationID() async throws -> String {
        applicationIDFetches += 1
        return "alt-application-id"
    }
}

private final class FakeTransport: EntertainmentTransport, @unchecked Sendable {
    var failFirstConnect = false
    private(set) var identities: [String] = []
    private(set) var sent: [Data] = []
    private(set) var closed = false
    var onDisconnect: (@Sendable (String) -> Void)?

    func connect(host: String, pskIdentity: String, psk: Data) async throws {
        identities.append(pskIdentity)
        if failFirstConnect, identities.count == 1 { throw HueError.streamTimeout }
    }

    func send(_ datagram: Data) { sent.append(datagram) }
    func close() { closed = true }
}

private final class FakeSource: AudioSource {
    var displayName = "Fake"
    var onFailure: ((String) -> Void)?
    private(set) var callback: (([Float], Double) -> Void)?
    private(set) var stopCount = 0

    func start(onSamples: @escaping ([Float], Double) -> Void) throws {
        callback = onSamples
    }

    func stop() { stopCount += 1 }
}

@MainActor
private func makeEngine(clientKey: String? = "05C37B87131DA78EA028CE0429AE3F94")
    -> (MusicSyncEngine, FakeEntertainment, FakeTransport)
{
    let entertainment = FakeEntertainment()
    let transport = FakeTransport()
    let config = HueConfig(bridgeIP: "192.168.1.134", appKey: "app-key", clientKey: clientKey)
    let engine = MusicSyncEngine(config: config, entertainment: entertainment, transport: transport)
    return (engine, entertainment, transport)
}

// MARK: - Tests

@MainActor
@Test func startStreamsFramesForZoneChannels() async throws {
    let (engine, entertainment, transport) = makeEngine()
    await engine.start(source: FakeSource())
    #expect(engine.state == .running)
    #expect(entertainment.started == ["bce767fc-ddba-4747-bec1-2313f5dfbbac"])
    #expect(transport.identities == ["app-key"])

    try await Task.sleep(for: .milliseconds(120))
    #expect(transport.sent.count >= 2)
    let frame = transport.sent[0]
    #expect(frame.count == 52 + 2 * 7) // 2 channels
    #expect(String(data: frame.prefix(9), encoding: .utf8) == "HueStream")
    await engine.stop()
}

@MainActor
@Test func missingClientKeyFailsFast() async {
    let (engine, entertainment, _) = makeEngine(clientKey: nil)
    await engine.start(source: FakeSource())
    guard case .error(let message) = engine.state else {
        Issue.record("expected error state")
        return
    }
    #expect(message.contains("HUE_CLIENTKEY"))
    #expect(entertainment.started.isEmpty)
}

@MainActor
@Test func retriesWithApplicationIDWhenFirstHandshakeFails() async {
    let (engine, entertainment, transport) = makeEngine()
    transport.failFirstConnect = true
    await engine.start(source: FakeSource())
    #expect(engine.state == .running)
    #expect(transport.identities == ["app-key", "alt-application-id"])
    #expect(entertainment.applicationIDFetches == 1)
    // Le REST start a été relancé pour rouvrir la fenêtre de handshake.
    #expect(entertainment.started.count == 2)
    #expect(entertainment.stopped.count == 1)
    await engine.stop()
}

@MainActor
@Test func stopTearsDownEverything() async {
    let (engine, entertainment, transport) = makeEngine()
    let source = FakeSource()
    await engine.start(source: source)
    await engine.stop()
    #expect(engine.state == .idle)
    #expect(transport.closed)
    #expect(source.stopCount == 1)
    #expect(entertainment.stopped.contains("bce767fc-ddba-4747-bec1-2313f5dfbbac"))
}

@MainActor
@Test func sourceFailureSurfacesError() async throws {
    let (engine, _, _) = makeEngine()
    let source = FakeSource()
    await engine.start(source: source)
    source.onFailure?("Périphérique audio déconnecté")
    try await Task.sleep(for: .milliseconds(50))
    #expect(engine.state == .error("Périphérique audio déconnecté"))
}

@MainActor
@Test func transportDisconnectSurfacesErrorAndTearsDown() async throws {
    let (engine, entertainment, transport) = makeEngine()
    let source = FakeSource()
    await engine.start(source: source)
    #expect(engine.state == .running)

    transport.onDisconnect?("connexion coupée")
    try await Task.sleep(for: .milliseconds(80))

    guard case .error(let message) = engine.state else {
        Issue.record("expected error state, got \(engine.state)")
        return
    }
    #expect(message.contains("connexion coupée"))
    #expect(transport.closed)
    #expect(source.stopCount == 1)
    #expect(entertainment.stopped.count == 1)
}

@MainActor
@Test func teardownFiresHookAndClearsZoneState() async {
    let (engine, entertainment, _) = makeEngine()
    var hookCalls = 0
    engine.onDidTeardown = { hookCalls += 1 }
    await engine.start(source: FakeSource())
    await engine.stop()
    #expect(hookCalls == 1)
    #expect(engine.zoneName == nil)

    // Un nouveau start qui échoue AVANT la redécouverte de zone ne doit pas
    // envoyer de stop parasite sur l'ancienne zone.
    let stopsBefore = entertainment.stopped.count
    entertainment.failFetches = true
    await engine.start(source: FakeSource())
    #expect(entertainment.stopped.count == stopsBefore)
    #expect(hookCalls == 2) // le teardown du chemin d'erreur a bien tourné
}

@MainActor
@Test func audioSamplesDriveTheLevel() async throws {
    let (engine, _, _) = makeEngine()
    let source = FakeSource()
    await engine.start(source: source)
    let loud = (0..<4096).map { i in Float(0.8 * sin(2.0 * .pi * 60 * Double(i) / 48_000)) }
    source.callback?(loud, 48_000)
    try await Task.sleep(for: .milliseconds(80))
    #expect(engine.level > 0.1)
    await engine.stop()
}
