import AppKit
import SwiftUI
import HueKit

struct RoomDetailView: View {
    let state: HueState
    let room: RoomModel
    @State private var showGallery = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var roomColor: Color = .white
    @State private var colorTask: Task<Void, Never>?
    @State private var capturing = false
    @State private var captureName = ""

    var body: some View {
        let tint = HueCardStyle.tint(for: room)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack {
                    Text("Scènes").font(.headline)
                    Spacer()
                    Button {
                        captureName = ""
                        capturing = true
                    } label: {
                        Label("Capturer", systemImage: "camera")
                    }
                    .controlSize(.small)
                    .disabled(room.lights.isEmpty)
                    .help("Créer une scène depuis l'état actuel des lampes")
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
        // Façon app Hue : la couleur de la pièce part du haut de la fenêtre et fond
        // dans l'arrière-plan (dégradé des couleurs réelles, masqué verticalement).
        .background(alignment: .top) {
            LinearGradient(colors: tint.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0),
                            .init(color: .black.opacity(0.55), location: 0.45),
                            .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
                .frame(height: 380)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showGallery) {
            GalleryView(state: state, roomID: room.id)
        }
        .alert("Scène depuis l'état actuel", isPresented: $capturing) {
            TextField("Nom de la scène", text: $captureName)
            Button("Créer") {
                let trimmed = captureName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    Task { await state.captureScene(roomID: room.id, name: trimmed) }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Fige l'éclairage actuel de la pièce (couleurs, luminosité, lampes éteintes).")
        }
    }

    /// Header façon app Hue : contrôles posés directement sur le dégradé pleine
    /// largeur (couleur réelle de la pièce), slider = moyenne des lampes allumées.
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

            // Couleur / température de toute la pièce, comme l'app Hue.
            HStack(spacing: 10) {
                if let mirekRange = HueCardStyle.roomMirekRange(room) {
                    Image(systemName: "thermometer.medium")
                        .font(.caption)
                        .foregroundStyle(tint.foreground.opacity(0.7))
                    TweenedSlider(target: HueCardStyle.averageMirek(room), range: mirekRange) { value in
                        Task { await state.setRoomTemperature(id: room.id, mirek: Int(value)) }
                    }
                    .controlSize(.small)
                    .tint(tint.foreground.opacity(0.85))
                    .help("Température de la pièce : froid ← → chaud")
                }
                if room.lights.contains(where: { $0.color != nil }) {
                    ColorPicker("", selection: $roomColor, supportsOpacity: false)
                        .labelsHidden()
                        .controlSize(.small)
                        .onChange(of: roomColor) { _, newValue in
                            // Écho du resync modèle→pastille : rien à envoyer si égal
                            // au modèle (sinon le PUT on:true rallumait la pièce).
                            if let modelColor = roomModelColor,
                               LightCardView.close(newValue, modelColor) { return }
                            scheduleRoomColorSend(newValue)
                        }
                        .help("Couleur de la pièce")
                }
            }
            .disabled(room.groupedLightID == nil || !tint.isOn)
            .opacity(tint.isOn ? 1 : 0.35)
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()) // clic droit possible sur toute la zone du header
        .onAppear { syncSwatchFromLights() }
        // Scène rappelée ou refresh : la pastille suit la couleur réelle de la pièce.
        .onChange(of: room.lights) { _, _ in syncSwatchFromLights() }
        .contextMenu {
            Button("Renommer la pièce…") {
                newName = room.name
                renaming = true
            }
        }
        .renameAlert("Renommer la pièce", isPresented: $renaming, name: $newName) { name in
            Task { await state.renameRoom(id: room.id, name: name) }
        }
    }

    /// Couleur de référence de la pièce : première lampe couleur allumée.
    private var roomModelColor: Color? {
        guard let xy = room.lights.first(where: { $0.on.on && $0.color != nil })?.color?.xy else { return nil }
        let rgb = HueColor.rgb(from: xy)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private func syncSwatchFromLights() {
        guard let modelColor = roomModelColor,
              !LightCardView.close(modelColor, roomColor) else { return }
        roomColor = modelColor
    }

    /// Comme sur les lampes : le ColorPicker émet en continu, on n'envoie que la dernière valeur.
    private func scheduleRoomColorSend(_ newColor: Color) {
        colorTask?.cancel()
        colorTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
            await state.setRoomColor(
                id: room.id,
                red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent
            )
        }
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
    @State private var renaming = false
    @State private var newName = ""

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
        .contextMenu {
            Button("Renommer la pièce…") {
                newName = room.name
                renaming = true
            }
        }
        .renameAlert("Renommer la pièce", isPresented: $renaming, name: $newName) { name in
            Task { await state.renameRoom(id: room.id, name: name) }
        }
    }
}
