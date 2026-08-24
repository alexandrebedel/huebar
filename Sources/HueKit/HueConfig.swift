import Foundation

public struct HueConfig: Sendable, Equatable {
    public var bridgeIP: String
    public var appKey: String

    public init(bridgeIP: String, appKey: String) {
        self.bridgeIP = bridgeIP
        self.appKey = appKey
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
        return HueConfig(bridgeIP: bridge, appKey: appKey)
    }
}
