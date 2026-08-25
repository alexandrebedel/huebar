import AppKit
import SwiftUI
import HueKit
import SyncKit

enum SidebarItem: Hashable {
    case home
    case room(String)
    case music
}

struct AppWindowView: View {
    let state: HueState
    var musicEngine: MusicSyncEngine?
    var recorder: RecorderController?
    @State private var selection: SidebarItem? = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            VStack(spacing: 0) {
                if case .error(let message) = state.status {
                    ErrorBanner(message: message, state: state)
                        .padding([.top, .horizontal], 12)
                }
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("Maison", systemImage: "house.fill")
                    .tag(SidebarItem.home)
                Section("Pièces") {
                    ForEach(state.rooms) { room in
                        Label(room.name, systemImage: "lamp.floor.fill")
                            .tag(SidebarItem.room(room.id))
                    }
                }
                Section("Studio") {
                    Label("Musique & REC", systemImage: "music.note")
                        .tag(SidebarItem.music)
                }
            }
            .listStyle(.sidebar)
            Divider()
            footer
        }
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
        .padding(10)
    }

    @ViewBuilder
    private var detail: some View {
        if state.rooms.isEmpty && state.status == .loading {
            Spacer()
            ProgressView()
            Spacer()
        } else {
            switch selection ?? .home {
            case .home:
                HomeDetailView(state: state)
            case .room(let id):
                if let room = state.rooms.first(where: { $0.id == id }) {
                    RoomDetailView(state: state, room: room)
                } else {
                    HomeDetailView(state: state)
                }
            case .music:
                if let musicEngine, let recorder {
                    ScrollView {
                        MusicSectionView(engine: musicEngine, recorder: recorder)
                            .padding(20)
                    }
                } else {
                    ContentUnavailableView(
                        "Musique indisponible",
                        systemImage: "music.note",
                        description: Text("Credentials Hue introuvables.")
                    )
                }
            }
        }
    }
}

private struct ErrorBanner: View {
    let message: String
    let state: HueState

    var body: some View {
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
