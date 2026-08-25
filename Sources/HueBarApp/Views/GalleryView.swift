import SwiftUI
import HueKit

/// Galerie de scénarios (recréée localement — l'API ne sert pas celle de l'app Hue) :
/// clic = appliquer aux lampes de la pièce, + = créer la scène sur le bridge.
struct GalleryView: View {
    let state: HueState
    let room: RoomModel
    @Environment(\.dismiss) private var dismiss
    @State private var savedNames: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Galerie — \(room.name)").font(.title3.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
            }
            Text("Clic : appliquer aux lampes · ⊕ : ajouter comme scène de la pièce")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SceneGallery.scenarios) { scenario in
                        GalleryCard(scenario: scenario, isSaved: isSaved(scenario)) {
                            Task { await state.applyScenario(roomID: room.id, scenario) }
                        } onSave: {
                            savedNames.insert(scenario.name)
                            Task { await state.saveScenario(roomID: room.id, scenario) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(width: 640, height: 500)
    }

    private func isSaved(_ scenario: GalleryScenario) -> Bool {
        savedNames.contains(scenario.name)
            || room.scenes.contains { $0.metadata.name == scenario.name }
    }
}

private struct GalleryCard: View {
    let scenario: GalleryScenario
    let isSaved: Bool
    let onApply: () -> Void
    let onSave: () -> Void
    @State private var hovering = false

    private var colors: [Color] {
        scenario.previewColors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .center, endPoint: .bottom)
            HStack {
                Text(scenario.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button(action: onSave) {
                    Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(isSaved)
                .help(isSaved ? "Déjà dans la pièce" : "Ajouter comme scène de la pièce")
            }
            .padding(10)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onApply() }
    }
}
