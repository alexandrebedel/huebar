import SwiftUI
import HueKit

/// Style de cartes façon app Hue : fond teinté par la couleur RÉELLE des lampes
/// quand c'est allumé, gris neutre quand c'est éteint, texte noir ou blanc selon
/// la luminance du fond.
enum HueCardStyle {
    struct Tint {
        let colors: [Color]
        let foreground: Color
        let isOn: Bool
    }

    private static let warmWhite = (red: 1.0, green: 0.84, blue: 0.62)

    static func tint(for room: RoomModel) -> Tint {
        guard room.isOn else { return offTint }
        var rgbs = room.lights.filter { $0.on.on }.map { rgb(of: $0) }
        if rgbs.isEmpty { rgbs = [warmWhite] }
        return onTint(rgbs)
    }

    static func tint(for light: Light) -> Tint {
        guard light.on.on else { return offTint }
        return onTint([rgb(of: light)])
    }

    /// Moyenne des lampes allumées — la valeur affichée par le slider d'une pièce
    /// (comme l'app Hue) ; retombe sur le dimming du grouped_light sans lampes allumées.
    static func averageBrightness(_ room: RoomModel) -> Double {
        let levels = room.lights.filter { $0.on.on }.compactMap { $0.dimming?.brightness }
        guard !levels.isEmpty else { return room.brightness }
        return levels.reduce(0, +) / Double(levels.count)
    }

    /// Plage mirek commune aux lampes CT de la pièce (intersection des schémas) ;
    /// nil sans lampe à température réglable.
    static func roomMirekRange(_ room: RoomModel) -> ClosedRange<Double>? {
        let ctLights = room.lights.filter { $0.colorTemperature != nil }
        guard !ctLights.isEmpty else { return nil }
        let schemas = ctLights.compactMap { $0.colorTemperature?.mirekSchema }
        guard let lower = schemas.map(\.mirekMinimum).max(),
              let upper = schemas.map(\.mirekMaximum).min(), lower < upper
        else { return 153...500 }
        return Double(lower)...Double(upper)
    }

    /// Mirek moyen des lampes CT allumées — la valeur du slider de température de pièce.
    static func averageMirek(_ room: RoomModel) -> Double {
        let mireks = room.lights.filter { $0.on.on }.compactMap { $0.colorTemperature?.mirek }
        guard !mireks.isEmpty else { return 370 }
        return Double(mireks.reduce(0, +)) / Double(mireks.count)
    }

    // MARK: - Interne

    private static var offTint: Tint {
        Tint(colors: [.gray.opacity(0.28), .gray.opacity(0.16)], foreground: .primary, isOn: false)
    }

    private static func onTint(_ rgbs: [(red: Double, green: Double, blue: Double)]) -> Tint {
        var colors = rgbs.prefix(4).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        if colors.count == 1, let only = rgbs.first {
            // Une seule couleur : fin assombrie pour garder du relief.
            colors.append(Color(red: only.red * 0.55, green: only.green * 0.55, blue: only.blue * 0.55))
        }
        let first = rgbs[0]
        let luminance = 0.299 * first.red + 0.587 * first.green + 0.114 * first.blue
        return Tint(
            colors: colors,
            foreground: luminance > 0.65 ? .black.opacity(0.78) : .white,
            isOn: true
        )
    }

    private static func rgb(of light: Light) -> (red: Double, green: Double, blue: Double) {
        guard let xy = light.color?.xy else { return warmWhite }
        return HueColor.rgb(from: xy)
    }
}

extension View {
    /// Fond de carte Hue : dégradé + coins arrondis.
    func hueCard(colors: [Color]) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
