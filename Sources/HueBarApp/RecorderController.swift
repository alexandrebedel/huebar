import AVFoundation
import Foundation
import Observation
import WaveKit

/// Pilote l'enregistrement WAV : réutilise la source de la sync quand elle capte déjà
/// le device, sinon démarre une capture dédiée. Indépendant du streaming lumières.
@MainActor
@Observable
final class RecorderController {
    private let recorder = Recorder()
    private var standaloneSource: DeviceInputSource?
    private weak var attachedSource: DeviceInputSource?
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var lastFileURL: URL?
    var errorMessage: String?

    /// Vrai quand l'enregistrement dépend de la source de la sync (pas de capture dédiée) :
    /// si la sync s'arrête, l'enregistrement doit être finalisé avec elle.
    var isSharingExternalSource: Bool { isRecording && standaloneSource == nil }

    func start(sharing syncSource: DeviceInputSource?,
               device: AudioInputDevice,
               pair: (left: Int, right: Int)) {
        guard !isRecording else { return }
        errorMessage = nil
        do {
            let source: DeviceInputSource
            if let syncSource, syncSource.hardwareFormat != nil {
                source = syncSource
            } else {
                let standalone = DeviceInputSource(device: device, channelPair: pair)
                standalone.onFailure = { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.errorMessage = message
                        self?.stop()
                    }
                }
                try standalone.start { _, _ in } // capture pure, aucune analyse
                standaloneSource = standalone
                source = standalone
            }
            guard let format = source.hardwareFormat else {
                throw AudioSourceError.engineStartFailed("format du périphérique inconnu")
            }
            try recorder.start(sampleRate: format.sampleRate)
            source.onRawBuffer = { [recorder] buffer in
                recorder.append(from: buffer, left: pair.left, right: pair.right)
            }
            attachedSource = source
            isRecording = true
            startedAt = recorder.startedAt
        } catch {
            standaloneSource?.stop()
            standaloneSource = nil
            errorMessage = "Enregistrement impossible : \(error.localizedDescription)"
        }
    }

    func stop() {
        guard isRecording || standaloneSource != nil else { return }
        attachedSource?.onRawBuffer = nil
        attachedSource = nil
        if let standaloneSource {
            standaloneSource.onFailure = nil
            standaloneSource.stop()
            self.standaloneSource = nil
        }
        lastFileURL = recorder.currentFileURL
        recorder.stop()
        isRecording = false
        startedAt = nil
    }
}
