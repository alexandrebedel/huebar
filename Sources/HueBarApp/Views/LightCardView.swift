import AppKit
import SwiftUI
import HueKit

/// Carte de lampe façon app Hue : fond teinté de sa couleur quand allumée,
/// grise quand éteinte (slider et pipette alors inactifs).
struct LightCardView: View {
    let state: HueState
    let roomID: String
    let light: Light
    @State private var color: Color = .white
    @State private var colorTask: Task<Void, Never>?
    @State private var renaming = false
    @State private var newName = ""
    @State private var gradientColors: [Color] = []
    @State private var gradientTask: Task<Void, Never>?

    var body: some View {
        let tint = HueCardStyle.tint(for: light)
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { light.on.on },
                    set: { _ in Task { await state.toggleLight(roomID: roomID, lightID: light.id) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Text(light.metadata.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint.foreground)
                    .lineLimit(1)

                Spacer()

                if let effectValues = light.effects?.effectValues, effectValues.count > 1 {
                    Menu {
                        ForEach(effectValues, id: \.self) { effect in
                            Button(Self.effectLabel(effect)) {
                                Task { await state.setLightEffect(roomID: roomID, lightID: light.id, effect: effect) }
                            }
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(tint.foreground.opacity(hasActiveEffect ? 1 : 0.55))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(!tint.isOn)
                    .help("Effets")
                }

                if light.color != nil {
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .controlSize(.small)
                        .onChange(of: color) { _, newValue in
                            // Écho du resync modèle→pastille (le picker renormalise et
                            // réécrit le binding) : rien à envoyer si égal au modèle —
                            // sinon le PUT on:true rallumait la lampe toute seule.
                            if let modelColor, Self.close(newValue, modelColor) { return }
                            scheduleColorSend(newValue)
                        }
                        .disabled(!tint.isOn)
                        .opacity(tint.isOn ? 1 : 0.4)
                }
            }
            if light.dimming != nil {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max")
                        .font(.caption)
                        .foregroundStyle(tint.foreground.opacity(0.7))
                    TweenedSlider(target: light.dimming?.brightness ?? 100, range: 1...100) { value in
                        Task { await state.setLightBrightness(roomID: roomID, lightID: light.id, value) }
                    }
                    .controlSize(.small)
                    .tint(tint.foreground.opacity(0.85))
                }
                .disabled(!tint.isOn)
                .opacity(tint.isOn ? 1 : 0.35)
            }
            if light.gradient != nil, !gradientColors.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "rainbow")
                        .font(.caption)
                        .foregroundStyle(tint.foreground.opacity(0.7))
                    ForEach(gradientColors.indices, id: \.self) { index in
                        ColorPicker("", selection: $gradientColors[index], supportsOpacity: false)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                    Spacer()
                }
                .onChange(of: gradientColors) { _, newValue in
                    // Écho du modèle (init/resync) : n'envoie que ce qui diffère vraiment.
                    let model = modelGradientColors
                    if newValue.count == model.count,
                       zip(newValue, model).allSatisfy({ Self.close($0, $1) }) { return }
                    scheduleGradientSend()
                }
                .disabled(!tint.isOn)
                .opacity(tint.isOn ? 1 : 0.4)
                .help("Dégradé : un point de couleur par pipette, réparti sur le bandeau")
            }
            if let colorTemperature = light.colorTemperature {
                HStack(spacing: 8) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption)
                        .foregroundStyle(tint.foreground.opacity(0.7))
                    TweenedSlider(
                        target: Double(colorTemperature.mirek ?? 370),
                        range: Double(colorTemperature.mirekSchema?.mirekMinimum ?? 153)
                            ... Double(colorTemperature.mirekSchema?.mirekMaximum ?? 500)
                    ) { value in
                        Task { await state.setLightTemperature(roomID: roomID, lightID: light.id, mirek: Int(value)) }
                    }
                    .controlSize(.small)
                    .tint(tint.foreground.opacity(0.85))
                }
                .disabled(!tint.isOn)
                .opacity(tint.isOn ? 1 : 0.35)
                .help("Température : froid ← → chaud")
            }
        }
        .hueCard(colors: tint.colors)
        .contextMenu {
            Button("Renommer la lampe…") {
                newName = light.metadata.name
                renaming = true
            }
        }
        .renameAlert("Renommer la lampe", isPresented: $renaming, name: $newName) { name in
            Task { await state.renameLight(roomID: roomID, lightID: light.id, name: name) }
        }
        // Une scène (ou un refresh) change la couleur du modèle : la pastille suit.
        // L'onChange du picker ignore cet écho (comparaison au modèle, pas de flag).
        .onChange(of: light.color) { _, _ in
            guard let modelColor, !Self.close(modelColor, color) else { return }
            color = modelColor
        }
        .onAppear {
            if let xy = light.color?.xy {
                let rgb = HueColor.rgb(from: xy)
                color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
            if let gradient = light.gradient {
                // Une pipette par point possible, initialisée sur l'état actuel du bandeau.
                let capable = min(max(gradient.pointsCapable ?? 5, 2), 5)
                var colors = gradient.points.map { point -> Color in
                    let rgb = HueColor.rgb(from: point.color.xy)
                    return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
                }
                if colors.isEmpty { colors = [color] }
                while colors.count < capable { colors.append(colors[colors.count - 1]) }
                gradientColors = Array(colors.prefix(capable))
            }
        }
    }

    /// Couleur du modèle (xy bridge) convertie pour l'affichage.
    private var modelColor: Color? {
        guard let xy = light.color?.xy else { return nil }
        let rgb = HueColor.rgb(from: xy)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Points du bandeau côté modèle, convertis pour l'affichage.
    private var modelGradientColors: [Color] {
        (light.gradient?.points ?? []).map { point in
            let rgb = HueColor.rgb(from: point.color.xy)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    /// Égalité approchée en sRGB — absorbe les allers-retours RGB↔xy et la
    /// renormalisation du ColorPicker (conversions d'espaces colorimétriques).
    static func close(_ first: Color, _ second: Color) -> Bool {
        guard let a = NSColor(first).usingColorSpace(.sRGB),
              let b = NSColor(second).usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.02
            && abs(a.greenComponent - b.greenComponent) < 0.02
            && abs(a.blueComponent - b.blueComponent) < 0.02
    }

    private var hasActiveEffect: Bool { light.activeEffect != nil }

    static func effectLabel(_ effect: String) -> String {
        switch effect {
        case "no_effect": "Aucun effet"
        case "candle": "Bougie"
        case "fire": "Cheminée"
        case "prism": "Prisme"
        case "sparkle": "Étincelles"
        case "opal": "Opale"
        case "glisten": "Scintillement"
        case "underwater": "Sous l'eau"
        case "cosmos": "Cosmos"
        case "sunbeam": "Rayon de soleil"
        case "enchant": "Enchanté"
        default: effect.capitalized
        }
    }

    /// Même débounce que la couleur : seul le dernier état des pipettes part au bridge.
    private func scheduleGradientSend() {
        gradientTask?.cancel()
        gradientTask = Task { [colors = gradientColors] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let rgbs = colors.compactMap { NSColor($0).usingColorSpace(.sRGB) }
                .map { (red: Double($0.redComponent), green: Double($0.greenComponent),
                        blue: Double($0.blueComponent)) }
            guard rgbs.count == colors.count else { return }
            await state.setLightGradient(roomID: roomID, lightID: light.id, colors: rgbs)
        }
    }

    /// Le ColorPicker émet en continu pendant le drag : on n'envoie que la dernière valeur (250 ms).
    private func scheduleColorSend(_ newColor: Color) {
        colorTask?.cancel()
        colorTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
            await state.setLightColor(
                roomID: roomID, lightID: light.id,
                red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent
            )
        }
    }
}
