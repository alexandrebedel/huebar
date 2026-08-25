import AVFoundation
import Foundation

/// Enregistre une paire de canaux en WAV 24-bit au sample rate natif du device
/// (AVAudioFile ne resample jamais : le fichier suit la source).
/// Écriture hors du thread audio : copie stéréo du buffer puis queue série.
/// `close()` finalise le header RIFF — sans lui, un crash laisse un header à zéro.
public final class Recorder {
    private let directory: URL
    private let writerQueue = DispatchQueue(label: "huebar.recorder.writer")
    private var file: AVAudioFile?
    private var stereoFormat: AVAudioFormat?
    public private(set) var currentFileURL: URL?
    public private(set) var startedAt: Date?

    public init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music/PX5", isDirectory: true)) {
        self.directory = directory
    }

    public var isRecording: Bool { file != nil }

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
        stereoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                     channels: 2, interleaved: false)
        currentFileURL = url
        startedAt = Date()
    }

    /// Extrait la paire (left, right) d'un buffer multi-canaux, copie en stéréo, écrit en asynchrone.
    /// Appelable depuis la queue du tap audio.
    public func append(from buffer: AVAudioPCMBuffer, left: Int, right: Int) {
        guard let file, let stereoFormat, let source = buffer.floatChannelData else { return }
        let frames = buffer.frameLength
        guard frames > 0,
              let stereo = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frames) else { return }
        stereo.frameLength = frames
        let channelCount = Int(buffer.format.channelCount)
        let leftIndex = min(left, channelCount - 1)
        let rightIndex = min(right, channelCount - 1)
        let byteCount = Int(frames) * MemoryLayout<Float>.size
        memcpy(stereo.floatChannelData![0], source[leftIndex], byteCount)
        memcpy(stereo.floatChannelData![1], source[rightIndex], byteCount)
        writerQueue.async {
            try? file.write(from: stereo)
        }
    }

    public func stop() {
        guard let file else { return }
        writerQueue.sync {} // draine les écritures en attente
        file.close()
        self.file = nil
        stereoFormat = nil
        startedAt = nil
    }
}
