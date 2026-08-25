import Foundation

public struct HueConfig: Sendable, Equatable {
    public var bridgeIP: String
    public var appKey: String
    /// Clé PSK du pairing (HUE_CLIENTKEY, hex) — requise pour le streaming Entertainment.
    public var clientKey: String?

    public init(bridgeIP: String, appKey: String, clientKey: String? = nil) {
        self.bridgeIP = bridgeIP
        self.appKey = appKey
        self.clientKey = clientKey
    }

    /// La clientkey décodée en 16 octets (le PSK attend les octets, pas la chaîne hex).
    public var clientKeyBytes: Data? {
        guard let clientKey, clientKey.count % 2 == 0 else { return nil }
        var bytes = Data(capacity: clientKey.count / 2)
        var index = clientKey.startIndex
        while index < clientKey.endIndex {
            let next = clientKey.index(index, offsetBy: 2)
            guard let byte = UInt8(clientKey[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    /// Lit un fichier env de la forme `export KEY=VALUE` (quotes et commentaires tolérés).
    public static func load(path: String? = nil) throws -> HueConfig {
        let resolved = path ?? ("~/.config/hue/credentials.env" as NSString).expandingTildeInPath
        guard let content = try? String(contentsOfFile: resolved, encoding: .utf8) else {
            throw HueError.missingCredentials(resolved)
        }
        var values: [String: String] = [:]
        for rawLine in content.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") { line = String(line.dropFirst("export ".count)) }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            values[key] = value
        }
        guard let bridge = values["HUE_BRIDGE"], let appKey = values["HUE_KEY"],
              !bridge.isEmpty, !appKey.isEmpty else {
            throw HueError.missingCredentials(resolved)
        }
        let clientKey = values["HUE_CLIENTKEY"].flatMap { $0.isEmpty ? nil : $0 }
        return HueConfig(bridgeIP: bridge, appKey: appKey, clientKey: clientKey)
    }
}
