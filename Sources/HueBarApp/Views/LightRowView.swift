import AppKit
import SwiftUI
import HueKit

struct LightRowView: View {
    let state: HueState
    let roomID: String
    let light: Light
    @State private var brightness: Double = 100
    @State private var color: Color = .white
    @State private var colorTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { light.on.on },
                    set: { _ in Task { await state.toggleLight(roomID: roomID, lightID: light.id) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

                Text(light.metadata.name)
                    .font(.callout)
                    .lineLimit(1)

                Spacer()

                if light.color != nil {
                    ColorPicker("", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .controlSize(.small)
                        .onChange(of: color) { _, newValue in
                            scheduleColorSend(newValue)
                        }
                }
            }
            if light.dimming != nil {
                Slider(value: $brightness, in: 1...100) { editing in
                    if !editing {
                        Task { await state.setLightBrightness(roomID: roomID, lightID: light.id, brightness) }
                    }
                }
                .controlSize(.mini)
            }
        }
        .padding(.leading, 4)
        .onAppear {
            brightness = light.dimming?.brightness ?? 100
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
