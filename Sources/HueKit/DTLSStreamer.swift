import Foundation
import Network
import os

/// Transport de datagrammes vers le bridge — abstrait pour les tests de SyncKit.
public protocol EntertainmentTransport: AnyObject, Sendable {
    func connect(host: String, pskIdentity: String, psk: Data) async throws
    func send(_ datagram: Data)
    func close()
    var onDisconnect: (@Sendable (String) -> Void)? { get set }
}

/// DTLS 1.2 + PSK vers le port 2100 du bridge (protocole Hue Entertainment).
/// Paramètres validés : PSK = clientkey décodée (16 octets), identity = application key,
/// ciphersuite TLS_PSK_WITH_AES_128_GCM_SHA256 (0x00A8) ajoutée explicitement,
/// versions min et max forcées à DTLS 1.2.
public final class DTLSStreamer: EntertainmentTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "huebar.dtls")
    private var connection: NWConnection?
    private var isReady = false
    public var onDisconnect: (@Sendable (String) -> Void)?

    public init() {}

    public func connect(host: String, pskIdentity: String, psk: Data) async throws {
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.establish(host: host, pskIdentity: pskIdentity, psk: psk) }
                group.addTask {
                    // Large fenêtre : le premier lancement peut attendre l'accord
                    // « Réseau local » de macOS pendant que la connexion est en .waiting.
                    try await Task.sleep(for: .seconds(10))
                    throw HueError.streamTimeout
                }
                try await group.next()
                group.cancelAll()
            }
        } catch {
            close()
            throw error
        }
    }

    private func establish(host: String, pskIdentity: String, psk: Data) async throws {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        let pskData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(sec, pskData as __DispatchData, identityData as __DispatchData)
        guard let psk128 = tls_ciphersuite_t(rawValue: 0x00A8) else { throw HueError.invalidResponse }
        sec_protocol_options_append_tls_ciphersuite(sec, psk128)
        sec_protocol_options_set_min_tls_protocol_version(sec, .DTLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .DTLSv12)

        let parameters = NWParameters(dtls: tls, udp: NWProtocolUDP.Options())
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 2100, using: parameters)
        queue.sync { self.connection = conn }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func resumeOnce(_ body: () -> Void) -> Bool {
                let first = resumed.withLock { alreadyResumed in
                    if alreadyResumed { return false }
                    alreadyResumed = true
                    return true
                }
                if first { body() }
                return first
            }
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isReady = true
                    _ = resumeOnce { continuation.resume() }
                case .failed(let error):
                    if !resumeOnce({ continuation.resume(throwing: error) }) {
                        self?.onDisconnect?(error.localizedDescription)
                    }
                case .cancelled:
                    _ = resumeOnce { continuation.resume(throwing: HueError.streamTimeout) }
                case .waiting:
                    break // retransmissions DTLS ou attente de la permission réseau local
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    public func send(_ datagram: Data) {
        queue.async { [weak self] in
            guard let self, self.isReady, let conn = self.connection else { return }
            conn.send(content: datagram, completion: .contentProcessed { _ in })
        }
    }

    public func close() {
        queue.async { [weak self] in
            self?.isReady = false
            self?.connection?.stateUpdateHandler = nil
            self?.connection?.cancel()
            self?.connection = nil
        }
    }
}
