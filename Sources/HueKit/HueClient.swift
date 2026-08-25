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

public final class HueClient: HueControlling, EntertainmentControlling, Sendable {
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

    public func createScene(name: String, groupID: String, actions: [SceneAction]) async throws {
        struct Body: Encodable {
            let type = "scene"
            let metadata: Metadata
            let group: ResourceRef
            let actions: [SceneAction]
        }
        _ = try await send("POST", "/clip/v2/resource/scene", body: try encode(Body(
            metadata: Metadata(name: name),
            group: ResourceRef(rid: groupID, rtype: "room"),
            actions: actions
        )))
    }

    // MARK: - EntertainmentControlling

    public func fetchEntertainmentConfigurations() async throws -> [EntertainmentConfig] {
        try await list("entertainment_configuration")
    }

    public func fetchEntertainmentServices() async throws -> [EntertainmentService] {
        try await list("entertainment")
    }

    public func startEntertainment(id: String) async throws {
        try await putEntertainmentAction(id: id, action: "start")
    }

    public func stopEntertainment(id: String) async throws {
        try await putEntertainmentAction(id: id, action: "stop")
    }

    /// L'identité PSK alternative (header `hue-application-id` de GET /auth/v1).
    public func fetchApplicationID() async throws -> String {
        let (_, response) = try await sendRaw("GET", "/auth/v1", body: nil)
        guard let appID = response.value(forHTTPHeaderField: "hue-application-id") else {
            throw HueError.invalidResponse
        }
        return appID
    }

    private func putEntertainmentAction(id: String, action: String) async throws {
        struct Body: Encodable { let action: String }
        _ = try await send("PUT", "/clip/v2/resource/entertainment_configuration/\(id)",
                           body: try encode(Body(action: action)))
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
        try await sendRaw(method, path, body: body).0
    }

    private func sendRaw(_ method: String, _ path: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "https://\(config.bridgeIP)\(path)") else {
            throw HueError.invalidResponse
        }
        // 6 s : le premier hit à froid (ARP, TLS, Wi-Fi en veille) dépasse facilement 2 s,
        // ce qui affichait « Bridge injoignable » à chaque lancement.
        var request = URLRequest(url: url, timeoutInterval: 6)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(config.appKey, forHTTPHeaderField: "hue-application-key")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HueError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw HueError.badStatus(http.statusCode) }
        return (data, http)
    }
}
