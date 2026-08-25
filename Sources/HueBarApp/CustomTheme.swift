import Foundation

/// Thème créé dans l'éditeur : mêmes ancres de teinte que les thèmes intégrés,
/// persisté en JSON dans les préférences.
struct CustomTheme: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var anchors: [Double]

    /// Identifiant de sélection stocké dans `musicTheme` (distinct des rawValue intégrés).
    var selectionID: String { "custom:\(id.uuidString)" }

    static func decodeList(_ raw: String) -> [CustomTheme] {
        guard let data = raw.data(using: .utf8),
              let themes = try? JSONDecoder().decode([CustomTheme].self, from: data) else { return [] }
        return themes
    }

    static func encodeList(_ themes: [CustomTheme]) -> String {
        guard let data = try? JSONEncoder().encode(themes) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
