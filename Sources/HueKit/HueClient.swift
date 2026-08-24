import Foundation

/// Accepte le certificat auto-signé du bridge, uniquement pour son host.
final class BridgeTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let host: String

    init(host: String) { self.host = host }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == host,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

public final class HueClient: HueControlling, Sendable {
    private let config: HueConfig
    private let session: URLSession

    public init(config: HueConfig, sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.config = config
        self.session = URLSession(
            configuration: sessionConfiguration,
            delegate: BridgeTrustDelegate(host: config.bridgeIP),
            delegateQueue: nil
        )
    }

    // MARK: - HueControlling

    public func fetchLights() async throws -> [Light] { try await list("light") }
    public func fetchRooms() async throws -> [Room] { try await list("room") }
    public func fetchScenes() async throws -> [HueScene] { try await list("scene") }
    public func fetchGroupedLights() async throws -> [GroupedLight] { try await list("grouped_light") }

    public func updateLight(id: String, _ update: LightUpdate) async throws {
        _ = try await send("PUT", "/clip/v2/resource/light/\(id)", body: try encode(update))
    }

    public func updateGroupedLight(id: String, _ update: LightUpdate) async throws {
        _ = try await send("PUT", "/clip/v2/resource/grouped_light/\(id)", body: try encode(update))
    }

    public func recallScene(id: String) async throws {
        struct Recall: Encodable { let action = "active" }
        struct Body: Encodable { let recall = Recall() }
        _ = try await send("PUT", "/clip/v2/resource/scene/\(id)", body: try encode(Body()))
    }

    // MARK: - Plomberie

    private func list<T: Decodable>(_ resource: String) async throws -> [T] {
        let data = try await send("GET", "/clip/v2/resource/\(resource)", body: nil)
        return try JSONDecoder().decode(HueResponse<T>.self, from: data).data
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func send(_ method: String, _ path: String, body: Data?) async throws -> Data {
        guard let url = URL(string: "https://\(config.bridgeIP)\(path)") else {
            throw HueError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.appKey, forHTTPHeaderField: "hue-application-key")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HueError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw HueError.badStatus(http.statusCode) }
        return data
    }
}
