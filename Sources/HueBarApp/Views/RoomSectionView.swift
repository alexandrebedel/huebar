import SwiftUI
import HueKit

struct RoomSectionView: View {
    let state: HueState
    let room: RoomModel
    @State private var brightness: Double = 100
    @State private var lightsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(room.name).font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { room.isOn },
                    set: { _ in Task { await state.toggleRoom(id: room.id) } }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }

            Slider(value: $brightness, in: 1...100) { editing in
                if !editing {
                    Task { await state.setRoomBrightness(id: room.id, brightness) }
                }
            }
            .controlSize(.small)
            .disabled(room.groupedLightID == nil)

            if !room.scenes.isEmpty {
                SceneChipsView(title: nil, scenes: room.scenes, state: state)
            }

            if !room.lights.isEmpty {
                DisclosureGroup("Lampes", isExpanded: $lightsExpanded) {
                    VStack(spacing: 6) {
                        ForEach(room.lights) { light in
                            LightRowView(state: state, roomID: room.id, light: light)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }

            Divider()
        }
        .onAppear { brightness = room.brightness }
        .onChange(of: room.brightness) { _, newValue in brightness = newValue }
    }
}
