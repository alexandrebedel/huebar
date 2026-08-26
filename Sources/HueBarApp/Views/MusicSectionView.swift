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
    @AppStorage("musicTuningClub") private var tuningClubStorage = ""
    @AppStorage("musicTuningChill") private var tuningChillStorage = ""
    @AppStorage("musicCustomThemes") private var customThemesStorage = ""
    @State private var editingTheme: CustomTheme?
    @State private var editingThemeIsNew = false
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
                        engine.tuning = loadTuning(for: mode) // chaque mode garde ses réglages
                        modeStorage = mode.rawValue
                    }
                }
            }

            // Thèmes : la palette de couleurs imposée au mapper, quel que soit le mode.
            // Grille adaptative : intégrés + customs + « + » sur autant de lignes que nécessaire.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(SyncTheme.allCases) { theme in
                    ThemeChip(label: theme.label, anchors: theme.hueAnchors,
                              isSelected: themeStorage == theme.rawValue) {
                        selectTheme(id: theme.rawValue, anchors: theme.hueAnchors)
                    }
                }
                ForEach(customThemes) { theme in
                    ThemeChip(label: theme.name, anchors: theme.anchors,
                              isSelected: themeStorage == theme.selectionID) {
                        selectTheme(id: theme.selectionID, anchors: theme.anchors)
                    }
                    .contextMenu {
                        Button("Modifier…") {
                            editingThemeIsNew = false
                            editingTheme = theme
                        }
                        Button("Supprimer", role: .destructive) {
                            deleteCustomTheme(theme)
                        }
                    }
                }
                Button {
                    editingThemeIsNew = true
                    editingTheme = CustomTheme(
                        id: UUID(), name: "",
                        anchors: [0.83, 0.5, 0.08, 0.62]) // départ varié, à retoucher
                } label: {
                    Image(systemName: "plus")
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Créer un thème")
            }

            // Scènes de la maison utilisables comme thèmes (teintes de leurs couleurs).
            if !sceneThemes.isEmpty {
                Text("Depuis vos scènes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sceneThemes, id: \.id) { entry in
                            ThemeChip(label: entry.name, anchors: entry.anchors,
                                      isSelected: themeStorage == "scene:\(entry.id)") {
                                selectTheme(id: "scene:\(entry.id)", anchors: entry.anchors)
                            }
                        }
                    }
                }
            }

            // Master de luminosité de la sync : toujours visible, persisté par mode.
            // À fond (2.0), les pics saturent : les lampes atteignent leur vrai maximum.
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: tuningBinding(\.brightness), in: 0.2...2.0)
                    .controlSize(.small)
                Image(systemName: "sun.max")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help("Luminosité globale des lumières pendant la sync")

            // Réglages fins du mapper, persistés par mode — ajustables pendant la sync.
            DisclosureGroup {
                VStack(spacing: 6) {
                    tuningRow("Sensibilité", value: tuningBinding(\.sensitivity), range: 0.4...2,
                              help: "Énergie lumineuse globale")
                    tuningRow("Attaque", value: tuningBinding(\.punch), range: 0.5...2,
                              help: "Réactivité aux transitoires (élevé = sec)")
                    if engine.mode == .club {
                        tuningRow("Flash", value: tuningBinding(\.flash), range: 0...0.6,
                                  help: "Poids du flash sur les beats")
                    }
                    HStack {
                        Spacer()
                        Button("Réinitialiser") {
                            engine.tuning = .default
                            saveTuning(.default, for: engine.mode)
                        }
                        .controlSize(.mini)
                        .disabled(engine.tuning == .default)
                    }
                }
                .padding(.top, 4)
            } label: {
                Label("Réglages fins", systemImage: "slider.horizontal.3")
                    .font(.subheadline)
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
                SyncVisualizer(engine: engine)
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
            engine.tuning = loadTuning(for: engine.mode)
            applyStoredTheme()
        }
        .sheet(item: $editingTheme) { theme in
            ThemeEditorView(theme: theme, isNew: editingThemeIsNew) { saved in
                saveCustomTheme(saved)
            }
        }
        .task { await loadZoneMap() }
        .onChange(of: state.rooms) { _, _ in
            rebuildEntries()
            // Un thème-scène sélectionné avant que les pièces soient chargées se résout ici.
            if themeStorage.hasPrefix("scene:") { applyStoredTheme() }
        }
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

    // MARK: - Thèmes

    private var customThemes: [CustomTheme] {
        CustomTheme.decodeList(customThemesStorage)
    }

    /// Scènes colorées de la maison converties en thèmes (dédupliquées par nom —
    /// « Tokyo » présent dans deux pièces n'apparaît qu'une fois).
    private var sceneThemes: [(id: String, name: String, anchors: [Double])] {
        var seenNames = Set<String>()
        var result: [(id: String, name: String, anchors: [Double])] = []
        for scene in state.rooms.flatMap(\.scenes) + (state.all?.scenes ?? []) {
            guard !seenNames.contains(scene.metadata.name) else { continue }
            let anchors = SceneGradient.hueAnchors(for: scene)
            guard anchors.count >= 2 else { continue } // scènes de blancs : teinte non significative
            seenNames.insert(scene.metadata.name)
            result.append((scene.id, scene.metadata.name, anchors))
        }
        return result
    }

    private func selectTheme(id: String, anchors: [Double]?) {
        themeStorage = id
        engine.themeAnchors = anchors
    }

    /// Restaure le thème persisté (intégré, custom ou scène) ; un custom disparu
    /// retombe sur Spectre, une scène pas encore chargée est retentée au refresh.
    private func applyStoredTheme() {
        if themeStorage.hasPrefix("scene:") {
            let sceneID = String(themeStorage.dropFirst("scene:".count))
            if let entry = sceneThemes.first(where: { $0.id == sceneID }) {
                engine.themeAnchors = entry.anchors
            }
            return
        }
        if let custom = customThemes.first(where: { $0.selectionID == themeStorage }) {
            engine.themeAnchors = custom.anchors
        } else {
            let builtin = SyncTheme(rawValue: themeStorage) ?? .spectre
            engine.themeAnchors = builtin.hueAnchors
        }
    }

    private func saveCustomTheme(_ theme: CustomTheme) {
        var themes = customThemes
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
        } else {
            themes.append(theme)
        }
        customThemesStorage = CustomTheme.encodeList(themes)
        selectTheme(id: theme.selectionID, anchors: theme.anchors)
    }

    private func deleteCustomTheme(_ theme: CustomTheme) {
        customThemesStorage = CustomTheme.encodeList(customThemes.filter { $0.id != theme.id })
        if themeStorage == theme.selectionID {
            selectTheme(id: SyncTheme.spectre.rawValue, anchors: SyncTheme.spectre.hueAnchors)
        }
    }

    // MARK: - Réglages fins

    private func tuningRow(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            Slider(value: value, in: range)
                .controlSize(.small)
        }
        .help(help)
    }

    private func tuningBinding(_ keyPath: WritableKeyPath<SyncTuning, Double>) -> Binding<Double> {
        Binding(
            get: { engine.tuning[keyPath: keyPath] },
            set: { newValue in
                engine.tuning[keyPath: keyPath] = newValue
                saveTuning(engine.tuning, for: engine.mode)
            }
        )
    }

    private func loadTuning(for mode: SyncMode) -> SyncTuning {
        let raw = mode == .club ? tuningClubStorage : tuningChillStorage
        guard let data = raw.data(using: .utf8),
              let tuning = try? JSONDecoder().decode(SyncTuning.self, from: data) else { return .default }
        return tuning
    }

    private func saveTuning(_ tuning: SyncTuning, for mode: SyncMode) {
        guard let data = try? JSONEncoder().encode(tuning) else { return }
        let raw = String(decoding: data, as: UTF8.self)
        if mode == .club { tuningClubStorage = raw } else { tuningChillStorage = raw }
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

/// Visualiseur : bandes spectrales, pulse de beat et couleurs réellement envoyées
/// par channel — pour juger le tuning d'un coup d'œil, sans regarder les lampes.
private struct SyncVisualizer: View {
    let engine: MusicSyncEngine

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 5) {
                band("Bass", engine.frame.bass, Color(red: 0.95, green: 0.30, blue: 0.35))
                band("Mid", engine.frame.mid, Color(red: 0.95, green: 0.60, blue: 0.25))
                band("High", engine.frame.high, Color(red: 0.95, green: 0.85, blue: 0.30))
            }

            Circle()
                .fill(.pink)
                .frame(width: 12, height: 12)
                .scaleEffect(engine.frame.beat ? 1.5 : 0.7)
                .opacity(engine.frame.beat ? 1 : 0.35)
                .animation(.easeOut(duration: 0.15), value: engine.frame.beat)
                .help("Beat détecté")

            // Chaleur du son (centroïde spectral) : froid à gauche, chaud à droite.
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.58, saturation: 0.8, brightness: 0.95),
                                 Color(hue: 0.80, saturation: 0.7, brightness: 0.9),
                                 Color(hue: 0.03, saturation: 0.85, brightness: 0.95)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: 46, height: 6)
                Circle()
                    .fill(.white)
                    .frame(width: 9, height: 9)
                    .shadow(radius: 1)
                    .offset(x: engine.frame.warmth * 37)
            }
            .help("Chaleur du son : la teinte suit ce curseur")

            Spacer()

            HStack(spacing: 4) {
                ForEach(engine.lastColors, id: \.channel) { channel in
                    Circle()
                        .fill(Color(red: channel.red, green: channel.green, blue: channel.blue))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                }
            }
            .help("Couleurs envoyées, un point par channel de la zone")
        }
        .frame(height: 48)
    }

    private func band(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            Capsule()
                .fill(color.opacity(0.9))
                .frame(width: 9, height: max(3, min(1, value) * 34))
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
    }
}

/// Pastille de thème : la palette de couleurs de la sync (intégré ou custom).
private struct ThemeChip: View {
    let label: String
    let anchors: [Double]?
    let isSelected: Bool
    let action: () -> Void

    private var colors: [Color] {
        guard let anchors, !anchors.isEmpty else {
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
                Text(label).font(.caption)
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
