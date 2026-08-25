import AVFoundation
import Foundation

/// Enregistre une paire de canaux en WAV 24-bit au sample rate natif du device
/// (AVAudioFile ne resample jamais : le fichier suit la source).
/// Écriture hors du thread audio : copie stéréo du buffer puis queue série.
/// `close()` finalise le header RIFF — sans lui, un crash laisse un header à zéro.
/// @unchecked : l'état partagé est déjà protégé (stateLock + writerQueue, cf. ci-dessous),
/// et `append` est conçu pour le thread audio pendant que start/stop restent au MainActor.
public final class Recorder: @unchecked Sendable {
    private let directory: URL
    private let writerQueue = DispatchQueue(label: "huebar.recorder.writer")
    private var file: AVAudioFile?
    // `append` tourne sur le thread du tap audio pendant que start/stop tournent sur le
    // MainActor : l'état partagé (actif + format) est protégé par un lock, et `file`
    // n'est touché après le start que depuis writerQueue.
    private let stateLock = NSLock()
    private var isActive = false
    private var stereoFormat: AVAudioFormat?
    public private(set) var currentFileURL: URL?
    public private(set) var startedAt: Date?

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/PX5", isDirectory: true)) {
        self.directory = directory
    }

    public var isRecording: Bool { stateLock.withLock { isActive } }

    public func start(sampleRate: Double, filePrefix: String = "PX5") throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss" // pas de ':' ni '/' dans un nom de fichier
        let url = directory.appendingPathComponent("\(filePrefix) \(formatter.string(from: Date())).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false, // décrit le FICHIER ; on écrit du float32 désentrelacé
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: settings,
                                      commonFormat: .pcmFormatFloat32, interleaved: false)
        file = newFile
        stateLock.withLock {
            stereoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 2, interleaved: false)
            isActive = true
        }
        currentFileURL = url
        startedAt = Date()
    }

    /// Extrait la paire (left, right) d'un buffer multi-canaux, copie en stéréo, écrit en asynchrone.
    /// Appelable depuis la queue du tap audio.
    public func append(from buffer: AVAudioPCMBuffer, left: Int, right: Int) {
        let format: AVAudioFormat? = stateLock.withLock { isActive ? stereoFormat : nil }
        guard let format, let source = buffer.floatChannelData else { return }
        let frames = buffer.frameLength
        guard frames > 0,
              let stereo = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        stereo.frameLength = frames
        let channelCount = Int(buffer.format.channelCount)
        let leftIndex = min(left, channelCount - 1)
        let rightIndex = min(right, channelCount - 1)
        let byteCount = Int(frames) * MemoryLayout<Float>.size
        memcpy(stereo.floatChannelData![0], source[leftIndex], byteCount)
        memcpy(stereo.floatChannelData![1], source[rightIndex], byteCount)
        writerQueue.async { [weak self] in
            guard let file = self?.file else { return }
            try? file.write(from: stereo)
        }
    }

    public func stop() {
        let wasActive = stateLock.withLock {
            let active = isActive
            isActive = false
            stereoFormat = nil
            return active
        }
        guard wasActive || file != nil else { return }
        writerQueue.sync { [self] in
            file?.close() // finalise le header RIFF — indispensable
            file = nil
        }
        startedAt = nil
    }
}
