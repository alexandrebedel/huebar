import Foundation
import HueKit
import Observation
import WaveKit
import os

/// Orchestration de la sync musique → lumières :
/// source audio → AudioAnalyzer (queue audio) → dernière frame partagée →
/// boucle 50 Hz (MainActor) → LightMapper → HueStreamEncoder → transport DTLS.
/// L'envoi continu à 50 Hz fait aussi office de keepalive (timeout bridge ~10 s).
@MainActor
@Observable
public final class MusicSyncEngine {
    public enum State: Equatable {
        case idle
        case starting
        case running
        case error(String)
    }

    public private(set) var state: State = .idle
    public private(set) var level: Double = 0
    public private(set) var zoneName: String?
    public var mode: SyncMode = .club {
        didSet { if mode != oldValue { mapper = LightMapper(mode: mode) } }
    }

    private let config: HueConfig
    private let entertainment: any EntertainmentControlling
    private let transport: any EntertainmentTransport
    private var mapper: LightMapper
    private var source: (any AudioSource)?
    private var configID: String?
    private var channels: [SyncChannel] = []
    private var loopTask: Task<Void, Never>?
    private let latestFrame = OSAllocatedUnfairLock(initialState: AnalysisFrame.silence)

    public init(config: HueConfig,
                entertainment: any EntertainmentControlling,
                transport: any EntertainmentTransport) {
        self.config = config
        self.entertainment = entertainment
        self.transport = transport
        self.mapper = LightMapper(mode: .club)
    }

    public func start(source: any AudioSource) async {
        guard state != .running, state != .starting else { return }
        guard let psk = config.clientKeyBytes else {
            state = .error("HUE_CLIENTKEY absente de ~/.config/hue/credentials.env")
            return
        }
        state = .starting
        do {
            let configs = try await entertainment.fetchEntertainmentConfigurations()
            guard let zone = configs.first(where: { $0.metadata.name == "HueBar Sync" }) ?? configs.first else {
                state = .error("Aucune zone Entertainment sur le bridge")
                return
            }
            configID = zone.id
            zoneName = zone.metadata.name
            channels = zone.channels.map { SyncChannel(id: $0.channelID, x: $0.position.x) }

            // Une coupure DTLS après le handshake (bridge redémarré, Wi-Fi) doit
            // remonter à l'UI — sinon l'engine reste « running » avec des lampes figées.
            transport.onDisconnect = { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self, self.state == .running || self.state == .starting else { return }
                    await self.teardown()
                    self.state = .error("Connexion au bridge perdue : \(message)")
                }
            }

            // REST start puis handshake immédiat (fenêtre de quelques secondes).
            try await entertainment.startEntertainment(id: zone.id)
            do {
                try await transport.connect(host: config.bridgeIP, pskIdentity: config.appKey, psk: psk)
            } catch {
                // Identité PSK alternative (hue-application-id) : certains firmwares l'exigent.
                // Rouvrir la fenêtre de handshake avant de retenter.
                try? await entertainment.stopEntertainment(id: zone.id)
                let applicationID = try await entertainment.fetchApplicationID()
                try await entertainment.startEntertainment(id: zone.id)
                try await transport.connect(host: config.bridgeIP, pskIdentity: applicationID, psk: psk)
            }

            try startAudio(source)
            self.source = source
            startLoop()
            state = .running
        } catch {
            await teardown()
            state = .error(Self.describe(error))
        }
    }

    public func stop() async {
        await teardown()
        state = .idle
    }

    // MARK: - Internals

    private func startAudio(_ source: any AudioSource) throws {
        source.onFailure = { [weak self] message in
            Task { @MainActor [weak self] in
                guard let self, self.state == .running || self.state == .starting else { return }
                await self.teardown()
                self.state = .error(message)
            }
        }
        let frameBox = latestFrame
        var analyzer: AudioAnalyzer?
        var analyzerRate = 0.0
        try source.start { samples, sampleRate in
            // Queue audio de la source — l'analyzer vit ici, jamais sur le MainActor.
            if analyzer == nil || analyzerRate != sampleRate {
                analyzer = AudioAnalyzer(sampleRate: sampleRate)
                analyzerRate = sampleRate
            }
            if let frame = analyzer?.process(samples: samples) {
                frameBox.withLock { $0 = frame }
            }
        }
    }

    private func startLoop() {
        loopTask = Task { [weak self] in
            var sequence: UInt8 = 0
            while !Task.isCancelled {
                guard let self else { return }
                let frame = self.latestFrame.withLock { $0 }
                self.level = min(1, frame.rms * 3)
                let colors = self.mapper.map(frame: frame, channels: self.channels,
                                             time: ProcessInfo.processInfo.systemUptime)
                if let configID = self.configID {
                    self.transport.send(HueStreamEncoder.frame(
                        configID: configID, sequence: sequence, channels: colors))
                }
                sequence &+= 1
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    private func teardown() async {
        loopTask?.cancel()
        loopTask = nil
        source?.stop()
        source?.onFailure = nil
        source = nil
        transport.onDisconnect = nil
        transport.close()
        if let configID {
            try? await entertainment.stopEntertainment(id: configID)
        }
        level = 0
        latestFrame.withLock { $0 = .silence }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case HueError.streamTimeout: "Connexion au bridge impossible (streaming)"
        case HueError.badStatus(let code): "Le bridge a refusé (HTTP \(code))"
        case let sourceError as AudioSourceError: "Audio : \(sourceError)"
        default: error.localizedDescription
        }
    }
}
