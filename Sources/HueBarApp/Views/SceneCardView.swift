import SwiftUI
import HueKit

struct SceneGridView: View {
    let scenes: [HueScene]
    let state: HueState

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(scenes) { scene in
                SceneCardView(scene: scene, state: state)
            }
        }
    }
}

/// Carte de scène : dégradé généré depuis les couleurs réelles des actions
/// (les images officielles de l'app Hue ne sont pas servies par l'API).
struct SceneCardView: View {
    let scene: HueScene
    let state: HueState
    @State private var hovering = false

    var body: some View {
        Button {
            Task { await state.recallScene(id: scene.id) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    startPoint: .center, endPoint: .bottom
                ) // scrim : le nom reste lisible sur les dégradés clairs
                Text(scene.metadata.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(10)
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var gradientColors: [Color] {
        let stops = SceneGradient.stops(for: scene)
        var colors = stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        if colors.count == 1, let stop = stops.first {
            // Une seule couleur : on assombrit la fin pour garder du relief.
            colors.append(Color(red: stop.red * 0.55, green: stop.green * 0.55, blue: stop.blue * 0.55))
        }
        return colors
    }
}
