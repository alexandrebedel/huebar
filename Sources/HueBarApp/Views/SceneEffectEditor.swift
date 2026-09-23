import SwiftUI
import HueKit

/// Réglage de l'effet d'une scène animée (clic droit sur sa carte) : type, vitesse,
/// luminosité. Chaque changement est réécrit dans la scène puis rejoué — on règle en
/// regardant les lampes. Les sliders n'envoient qu'au relâché (réécriture + recall).
struct SceneEffectEditor: View {
    let sceneID: String
    let sceneName: String
    let effects: [String]
    let hasSpeed: Bool
    let state: HueState
    @State var settings: SceneEffectSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sceneName).font(.headline)
            Picker("Effet", selection: $settings.effect) {
                // L'effet courant reste listé même si une lampe ne le propose plus.
                ForEach(effects.contains(settings.effect) ? effects : [settings.effect] + effects,
                        id: \.self) { effect in
                    Text(LightCardView.effectLabel(effect)).tag(effect)
                }
            }
            .onChange(of: settings.effect) { _, _ in send() }
            if hasSpeed {
                slider("Vitesse", value: $settings.speed, in: 0...1,
                       display: settings.speed.formatted(.number.precision(.fractionLength(2))))
            }
            slider("Luminosité", value: $settings.brightness, in: 1...100,
                   display: "\(Int(settings.brightness.rounded())) %")
            Text("Hue n'expose pas l'intensité d'un effet : pour plus de contraste, essaie un autre effet ou monte la luminosité.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300)
    }

    private func slider(
        _ title: String, value: Binding<Double>, in range: ClosedRange<Double>, display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range) { editing in
                if !editing { send() }
            }
        }
    }

    private func send() {
        Task { await state.updateSceneEffect(id: sceneID, settings) }
    }
}
