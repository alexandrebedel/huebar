import SwiftUI
import HueKit

struct RoomDetailView: View {
    let state: HueState
    let room: RoomModel
    @State private var brightness: Double = 100

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !room.scenes.isEmpty {
                    SceneGridView(scenes: room.scenes, state: state)
                }
                if !room.lights.isEmpty {
                    Text("Lampes").font(.headline)
                    VStack(spacing: 8) {
                        ForEach(room.lights) { light in
                            LightRowView(state: state, roomID: room.id, light: light)
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear { brightness = room.brightness }
        .onChange(of: room.brightness) { _, newValue in brightness = newValue }
        .onChange(of: room.id) { _, _ in brightness = room.brightness }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(room.name).font(.title.bold())
                Spacer()
                Toggle("", isOn: Binding(
                    get: { room.isOn },
                    set: { _ in Task { await state.toggleRoom(id: room.id) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Slider(value: $brightness, in: 1...100) { editing in
                if !editing {
                    Task { await state.setRoomBrightness(id: room.id, brightness) }
                }
            }
            .disabled(room.groupedLightID == nil)
        }
    }
}

/// Vue « Maison » : l'interrupteur global et les scènes de toute la maison.
struct HomeDetailView: View {
    let state: HueState

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
                if let all = state.all, !all.scenes.isEmpty {
                    SceneGridView(scenes: all.scenes, state: state)
                }
            }
            .padding(20)
        }
    }
}
