import SwiftUI
import HueKit

/// Galerie de scénarios (recréée localement — l'API ne sert pas celle de l'app Hue) :
/// clic = appliquer aux lampes de la pièce, + = créer la scène sur le bridge.
struct GalleryView: View {
    let state: HueState
    let roomID: String
    @Environment(\.dismiss) private var dismiss
    @State private var savedNames: Set<String> = []
    /// Rayon affiché ; nil = tout.
    @State private var category: GalleryScenario.Category?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]

    /// Pièce lue en direct dans l'état : les ajouts/retraits re-partitionnent la galerie.
    private var room: RoomModel? {
        state.rooms.first { $0.id == roomID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Galerie — \(room?.name ?? "")").font(.title3.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
            }
            Text("Clic : appliquer aux lampes · ⊕ : ajouter comme scène · ⊖ : retirer")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("", selection: $category) {
                Text("Tout").tag(GalleryScenario.Category?.none)
                ForEach(GalleryScenario.Category.allCases) { category in
                    Text(category.title).tag(GalleryScenario.Category?.some(category))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if category == .horror {
                Label("Tamisées pour regarder un film. Pour que les lampes réagissent au son : "
                      + "Musique & REC → mode « Film d'horreur ».",
                      systemImage: "popcorn.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Les scénarios pas encore dans la pièce d'abord.
                    grid(for: pendingScenarios)
                    if !addedScenarios.isEmpty {
                        Text("Scènes ajoutées")
                            .font(.headline)
                            .padding(.top, 8)
                        grid(for: addedScenarios)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(width: 640, height: 500)
    }

    private func grid(for scenarios: [GalleryScenario]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(scenarios) { scenario in
                GalleryCard(scenario: scenario, isSaved: isSaved(scenario)) {
                    Task { await state.applyScenario(roomID: roomID, scenario) }
                } onSave: {
                    savedNames.insert(scenario.name)
                    Task { await state.saveScenario(roomID: roomID, scenario) }
                } onRemove: {
                    savedNames.remove(scenario.name)
                    if let scene = room?.scenes.first(where: { $0.metadata.name == scenario.name }) {
                        Task { await state.deleteScene(id: scene.id) }
                    }
                }
            }
        }
    }

    private var visibleScenarios: [GalleryScenario] {
        guard let category else { return SceneGallery.scenarios }
        return SceneGallery.scenarios.filter { $0.category == category }
    }

    private var pendingScenarios: [GalleryScenario] {
        visibleScenarios.filter { !isSaved($0) }
    }

    private var addedScenarios: [GalleryScenario] {
        visibleScenarios.filter { isSaved($0) }
    }

    private func isSaved(_ scenario: GalleryScenario) -> Bool {
        savedNames.contains(scenario.name)
            || room?.scenes.contains { $0.metadata.name == scenario.name } == true
    }
}

private struct GalleryCard: View {
    let scenario: GalleryScenario
    let isSaved: Bool
    let onApply: () -> Void
    let onSave: () -> Void
    let onRemove: () -> Void
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
                Button(action: isSaved ? onRemove : onSave) {
                    Image(systemName: isSaved ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help(isSaved ? "Retirer la scène de la pièce" : "Ajouter comme scène de la pièce")
            }
            .padding(10)
        }
        .frame(height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .overlay(alignment: .topTrailing) {
            if scenario.isAnimated {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(4)
                    .background(.black.opacity(0.3), in: Circle())
                    .padding(6)
                    .help("Scintille (effet natif des lampes)")
            }
        }
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onApply() }
    }
}
