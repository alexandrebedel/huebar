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
                TweenedSlider(target: light.dimming?.brightness ?? 100, range: 1...100) { value in
                    Task { await state.setLightBrightness(roomID: roomID, lightID: light.id, value) }
                }
                .controlSize(.small)
                .tint(tint.foreground.opacity(0.85))
                .disabled(!tint.isOn)
                .opacity(tint.isOn ? 1 : 0.35)
            }
        }
        .hueCard(colors: tint.colors)
        .onAppear {
            if let xy = light.color?.xy {
                let rgb = HueColor.rgb(from: xy)
                color = Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
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
