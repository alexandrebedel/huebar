import AppKit
import SwiftUI
import HueKit
import SyncKit
import WaveKit

struct MusicSectionView: View {
    let engine: MusicSyncEngine
    let recorder: RecorderController
    @AppStorage("musicSourceUID") private var sourceUID = "system"
    @AppStorage("musicPairIndex") private var pairIndex = 0
    @State private var devices: [AudioInputDevice] = []
    @State private var activeSyncSource: DeviceInputSource?

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
                Picker("", selection: Bindable(engine).mode) {
                    ForEach(SyncMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .labelsHidden()
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
        }
        .onChange(of: engine.state) { _, newState in
            // La source partagée est morte avec la sync : finaliser le fichier proprement.
            if case .error = newState, recorder.isRecording, activeSyncSource != nil {
                recorder.stop()
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
            await engine.stop()
            activeSyncSource = nil
            return
        }
        guard let source = makeSource() else { return }
        await engine.start(source: source)
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
