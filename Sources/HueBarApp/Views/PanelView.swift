import AppKit
import SwiftUI
import HueKit
import SyncKit

struct PanelView: View {
    let state: HueState
    var musicEngine: MusicSyncEngine?
    var recorder: RecorderController?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if case .error(let message) = state.status {
                errorBanner(message)
            }
            content
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("HueBar").font(.title3.bold())
            Spacer()
            if let all = state.all {
                Button {
                    Task { await state.toggleAll() }
                } label: {
                    Label(all.isOn ? "Tout éteindre" : "Tout allumer",
                          systemImage: all.isOn ? "lightbulb.slash" : "lightbulb.fill")
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.rooms.isEmpty && state.status == .loading {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 30)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let musicEngine, let recorder {
                        MusicSectionView(engine: musicEngine, recorder: recorder)
                    }
                    if let all = state.all, !all.scenes.isEmpty {
                        SceneChipsView(title: "Maison", scenes: all.scenes, state: state)
                    }
                    ForEach(state.rooms) { room in
                        RoomSectionView(state: state, room: room)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 520)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button("Réessayer") {
                Task { await state.refresh() }
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack {
            SettingsMenu()
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Rafraîchir")
        }
    }
}

private struct SettingsMenu: View {
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Menu {
            Toggle("Ouvrir au login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LoginItem.set(newValue)
                }
            Divider()
            Button("Quitter HueBar") {
                NSApp.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
