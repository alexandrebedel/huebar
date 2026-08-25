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
        .onAppear {
            if let xy = light.color?.xy {
                let rgb = HueColor.rgb(from: xy)
                color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
        }
    }

    private var hasActiveEffect: Bool {
        if let status = light.effects?.status { status != "no_effect" } else { false }
    }

    private static func effectLabel(_ effect: String) -> String {
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
