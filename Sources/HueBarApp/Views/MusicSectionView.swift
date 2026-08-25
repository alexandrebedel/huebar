import AppKit
import SwiftUI
import HueKit
import SyncKit
import WaveKit

struct MusicSectionView: View {
    let engine: MusicSyncEngine
    let recorder: RecorderController
    let state: HueState
    var entertainment: (any EntertainmentControlling)?
    @AppStorage("musicSourceUID") private var sourceUID = "system"
    @AppStorage("musicPairIndex") private var pairIndex = 0
    @AppStorage("musicMutedRooms") private var mutedRoomsStorage = ""
    @AppStorage("musicMode") private var modeStorage = SyncMode.club.rawValue
    @AppStorage("musicTheme") private var themeStorage = SyncTheme.spectre.rawValue
    @State private var devices: [AudioInputDevice] = []
    @State private var activeSyncSource: DeviceInputSource?
    @State private var zone: EntertainmentConfig?
    @State private var services: [EntertainmentService] = []
    @State private var zoneEntries: [ChannelRoomEntry] = []

    private var selectedDevice: AudioInputDevice? {
        devices.first { $0.uid == sourceUID }
    }

    private var isRunning: Bool {
        engine.state == .running || engine.state == .starting
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Musique", systemImage: "music.note")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                Spacer()
            }

            // Scènes musique : les modes du mapper présentés comme des cartes.
            HStack(spacing: 10) {
                ForEach(SyncMode.allCases) { mode in
                    MusicModeCard(mode: mode, isSelected: engine.mode == mode) {
                        engine.mode = mode
                        modeStorage = mode.rawValue
                    }
                }
            }

            // Thèmes : la palette de couleurs imposée au mapper, quel que soit le mode.
            HStack(spacing: 8) {
                ForEach(SyncTheme.allCases) { theme in
                    ThemeChip(theme: theme, isSelected: engine.theme == theme) {
                        engine.theme = theme
                        themeStorage = theme.rawValue
                    }
                }
            }

            HStack(spacing: 8) {
                Picker("", selection: $sourceUID) {
                    Text("Audio du Mac").tag("system")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                .labelsHidden()
                .disabled(isRunning)
                .onChange(of: sourceUID) { _, _ in
                    if let device = selectedDevice {
                        pairIndex = AudioDeviceCatalog.defaultPairIndex(for: device)
                    }
                }

                Button {
                    Task { await toggle() }
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                }
                .disabled(engine.state == .starting)
                .help(isRunning ? "Arrêter la sync" : "Lancer la sync lumières")
            }

            if let device = selectedDevice, device.channelCount > 2 {
                Picker("Canaux", selection: $pairIndex) {
                    ForEach(Array(device.channelPairs.enumerated()), id: \.offset) { index, pair in
                        Text(pair.label).tag(index)
                    }
                }
                .font(.caption)
                .disabled(isRunning)
            }

            if !syncRooms.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pièces synchronisées").font(.subheadline.weight(.semibold))
                    ForEach(syncRooms) { room in
                        Toggle(room.name, isOn: Binding(
                            get: { !mutedRoomIDs.contains(room.id) },
                            set: { setRoomMuted(room.id, muted: !$0) }
                        ))
                        .font(.callout)
                    }
                    Text("Une pièce décochée garde son éclairage actuel pendant la sync.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if isRunning {
                ProgressView(value: engine.level)
                    .tint(engine.level > 0.02 ? .green : .orange)
                if engine.level < 0.02 {
                    Text(sourceUID == "system"
                         ? "Aucun signal — joue de la musique. Si rien ne bouge, autorise HueBar dans Réglages → Confidentialité et sécurité → Enregistrement de l'écran et audio du système."
                         : "Aucun signal sur cette entrée — vérifie la source et la paire de canaux (PX5 : switch arrière USB 9-10 sur MST).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if selectedDevice != nil {
                recordRow
            }

            if case .error(let message) = engine.state {
                Text(message).font(.caption).foregroundStyle(.red)
            }

            Divider()
        }
        .onAppear {
            devices = AudioDeviceCatalog.inputDevices()
            engine.mode = SyncMode(rawValue: modeStorage) ?? .club
            engine.theme = SyncTheme(rawValue: themeStorage) ?? .spectre
        }
        .task { await loadZoneMap() }
        .onChange(of: state.rooms) { _, _ in rebuildEntries() }
        .onChange(of: engine.state) { _, newState in
            // Toute sortie de .running tue la source de la sync : un enregistrement qui la
            // partageait doit être finalisé (un REC standalone, lui, survit).
            if newState != .running, newState != .starting, recorder.isSharingExternalSource {
                recorder.stop()
            }
            if case .error = newState {
                activeSyncSource = nil
            }
        }
    }

    private var recordRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggleRecord()
                } label: {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.title3)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help(recorder.isRecording ? "Arrêter l'enregistrement" : "Enregistrer cette entrée en WAV")

                if recorder.isRecording, let startedAt = recorder.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Self.durationLabel(from: startedAt, to: context.date))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                    Spacer()
                } else if let lastFile = recorder.lastFileURL {
                    Text(lastFile.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Afficher") {
                        NSWorkspace.shared.activateFileViewerSelecting([lastFile])
                    }
                    .controlSize(.mini)
                } else {
                    Text("REC → ~/Music/PX5 (WAV 24-bit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if let recordError = recorder.errorMessage {
                Text(recordError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func toggle() async {
        if isRunning {
            // Un REC accroché à la source de la sync mourrait silencieusement avec elle.
            if recorder.isSharingExternalSource {
                recorder.stop()
            }
            await engine.stop()
            activeSyncSource = nil
            return
        }
        guard let source = makeSource() else { return }
        applyRoomFilter() // fige les couleurs ACTUELLES des pièces exclues
        await engine.start(source: source)
    }

    // MARK: - Filtre par pièces

    private var mutedRoomIDs: Set<String> {
        Set(mutedRoomsStorage.split(separator: ",").map(String.init))
    }

    private var syncRooms: [RoomModel] {
        let roomIDs = Set(zoneEntries.map(\.roomID))
        return state.rooms.filter { roomIDs.contains($0.id) }
    }

    private func setRoomMuted(_ roomID: String, muted: Bool) {
        var ids = mutedRoomIDs
        if muted { ids.insert(roomID) } else { ids.remove(roomID) }
        mutedRoomsStorage = ids.sorted().joined(separator: ",")
        applyRoomFilter()
    }

    private func loadZoneMap() async {
        guard let entertainment,
              let configs = try? await entertainment.fetchEntertainmentConfigurations(),
              let zone = MusicSyncEngine.pickZone(configs),
              let services = try? await entertainment.fetchEntertainmentServices() else { return }
        self.zone = zone
        self.services = services
        rebuildEntries()
    }

    private func rebuildEntries() {
        guard let zone else { return }
        let rooms = state.rooms.map { (id: $0.id, deviceIDs: Set($0.lights.map(\.owner.rid))) }
        zoneEntries = SyncRoomMap.entries(config: zone, services: services, rooms: rooms)
        applyRoomFilter()
    }

    private func applyRoomFilter() {
        var held: [UInt8: ChannelColor] = [:]
        let muted = mutedRoomIDs
        for entry in zoneEntries where muted.contains(entry.roomID) {
            held[entry.channel] = holdColor(for: entry)
        }
        engine.heldChannels = held
    }

    /// Couleur actuelle de la lampe du channel (noir si éteinte) — envoyée telle quelle
    /// pendant la sync pour que la pièce exclue garde son éclairage.
    private func holdColor(for entry: ChannelRoomEntry) -> ChannelColor {
        let light = state.rooms.first { $0.id == entry.roomID }?
            .lights.first { $0.owner.rid == entry.deviceID }
        guard let light, light.on.on else {
            return ChannelColor(channel: entry.channel, red: 0, green: 0, blue: 0)
        }
        let rgb = light.color.map { HueColor.rgb(from: $0.xy) } ?? (red: 1.0, green: 0.84, blue: 0.62)
        let value = (light.dimming?.brightness ?? 100) / 100
        return ChannelColor(
            channel: entry.channel,
            red: rgb.red * value, green: rgb.green * value, blue: rgb.blue * value)
    }

    private func toggleRecord() {
        if recorder.isRecording {
            recorder.stop()
            return
        }
        guard let device = selectedDevice else { return }
        let pairs = device.channelPairs
        guard !pairs.isEmpty else { return }
        let pair = pairs[min(pairIndex, pairs.count - 1)]
        let sharedSource = (isRunning && sourceUID == device.uid) ? activeSyncSource : nil
        recorder.start(sharing: sharedSource, device: device, pair: (pair.left, pair.right))
    }

    private func makeSource() -> (any AudioSource)? {
        if sourceUID == "system" {
            activeSyncSource = nil
            return SystemAudioTap()
        }
        guard let device = selectedDevice else { return nil }
        let pairs = device.channelPairs
        guard !pairs.isEmpty else { return nil }
        let pair = pairs[min(pairIndex, pairs.count - 1)]
        let source = DeviceInputSource(device: device, channelPair: (pair.left, pair.right))
        activeSyncSource = source
        return source
    }

    private static func durationLabel(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}

/// Pastille de thème : la palette de couleurs de la sync.
private struct ThemeChip: View {
    let theme: SyncTheme
    let isSelected: Bool
    let action: () -> Void

    private var colors: [Color] {
        guard let anchors = theme.hueAnchors else {
            return [0.0, 0.17, 0.33, 0.5, 0.67, 0.83].map {
                Color(hue: $0, saturation: 0.85, brightness: 1)
            }
        }
        return anchors.map { Color(hue: $0, saturation: 0.85, brightness: 1) }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AngularGradient(colors: colors + [colors[0]], center: .center))
                    .frame(width: 16, height: 16)
                Text(theme.label).font(.caption)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

/// Carte de « scène musique » : un mode du mapper, présenté comme une scène.
private struct MusicModeCard: View {
    let mode: SyncMode
    let isSelected: Bool
    let action: () -> Void

    private var colors: [Color] {
        switch mode {
        case .club: [Color(red: 0.55, green: 0.15, blue: 0.95), Color(red: 0.95, green: 0.20, blue: 0.55)]
        case .chill: [Color(red: 0.95, green: 0.60, blue: 0.25), Color(red: 0.85, green: 0.35, blue: 0.45)]
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: mode == .club ? "waveform.path" : "moon.stars.fill")
                Text(mode.label).font(.callout.weight(.semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.white.opacity(isSelected ? 0.85 : 0), lineWidth: 2))
            .opacity(isSelected ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }
}
