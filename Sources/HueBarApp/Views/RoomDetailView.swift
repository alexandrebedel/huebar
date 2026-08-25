import SwiftUI
import HueKit

struct RoomDetailView: View {
    let state: HueState
    let room: RoomModel
    @State private var showGallery = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack {
                    Text("Scènes").font(.headline)
                    Spacer()
                    Button {
                        showGallery = true
                    } label: {
                        Label("Galerie", systemImage: "photo.on.rectangle.angled")
                    }
                    .controlSize(.small)
                }
                if !room.scenes.isEmpty {
                    SceneGridView(scenes: room.scenes, state: state)
                }
                if !room.lights.isEmpty {
                    Text("Lampes").font(.headline)
                    VStack(spacing: 10) {
                        ForEach(room.lights) { light in
                            LightCardView(state: state, roomID: room.id, light: light)
                        }
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showGallery) {
            GalleryView(state: state, room: room)
        }
    }

    /// Header façon app Hue : grande carte teintée de la couleur réelle de la pièce,
    /// slider intégré (moyenne des lampes allumées), le tout grisé quand c'est éteint.
    private var header: some View {
        let tint = HueCardStyle.tint(for: room)
        return VStack(spacing: 12) {
            HStack {
                Text(room.name)
                    .font(.title.bold())
                    .foregroundStyle(tint.foreground)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { room.isOn },
                    set: { _ in Task { await state.toggleRoom(id: room.id) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            TweenedSlider(target: HueCardStyle.averageBrightness(room), range: 1...100) { value in
                Task { await state.setRoomBrightness(id: room.id, value) }
            }
            .tint(tint.foreground.opacity(0.85))
            .disabled(room.groupedLightID == nil || !tint.isOn)
            .opacity(tint.isOn ? 1 : 0.35)
        }
        .hueCard(colors: tint.colors)
    }
}

/// Vue « Maison » : interrupteur global, cartes de pièces (clic = ouvrir la pièce)
/// et scènes de toute la maison.
struct HomeDetailView: View {
    let state: HueState
    var onOpenRoom: (String) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Maison").font(.title.bold())
                    Spacer()
                    if let all = state.all {
                        Button {
                            Task { await state.toggleAll() }
                        } label: {
                            Label(all.isOn ? "Tout éteindre" : "Tout allumer",
                                  systemImage: all.isOn ? "lightbulb.slash" : "lightbulb.fill")
                        }
                    }
                }
                if !state.rooms.isEmpty {
                    Text("Pièces").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(state.rooms) { room in
                            RoomCardView(state: state, room: room) { onOpenRoom(room.id) }
                        }
                    }
                }
                if let all = state.all, !all.scenes.isEmpty {
                    Text("Scènes").font(.headline)
                    SceneGridView(scenes: all.scenes, state: state)
                }
            }
            .padding(20)
        }
    }
}

/// Carte de pièce sur la vue Maison : teinte réelle, toggle, slider ; un clic
/// hors des contrôles ouvre la pièce.
private struct RoomCardView: View {
    let state: HueState
    let room: RoomModel
    var onOpen: () -> Void

    var body: some View {
        let tint = HueCardStyle.tint(for: room)
        VStack(spacing: 10) {
            HStack {
                Text(room.name)
                    .font(.headline)
                    .foregroundStyle(tint.foreground)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { room.isOn },
                    set: { _ in Task { await state.toggleRoom(id: room.id) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            TweenedSlider(target: HueCardStyle.averageBrightness(room), range: 1...100) { value in
                Task { await state.setRoomBrightness(id: room.id, value) }
            }
            .controlSize(.small)
            .tint(tint.foreground.opacity(0.85))
            .disabled(room.groupedLightID == nil || !tint.isOn)
            .opacity(tint.isOn ? 1 : 0.35)
        }
        .hueCard(colors: tint.colors)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onOpen() }
    }
}
