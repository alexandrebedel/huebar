import AVFoundation
import CoreAudio
import Foundation

/// Capture une paire de canaux d'un périphérique d'entrée (ex. Xone:PX5 en USB).
/// Fournit aussi les buffers bruts multi-canaux via `onRawBuffer` (enregistrement).
public final class DeviceInputSource: AudioSource {
    private let engine = AVAudioEngine()
    private let device: AudioInputDevice
    private let channelPair: (left: Int, right: Int)
    private var configurationObserver: NSObjectProtocol?

    public var onFailure: ((String) -> Void)?
    /// Buffers bruts du tap (tous canaux, format hardware) — consommés par le Recorder.
    public var onRawBuffer: ((AVAudioPCMBuffer) -> Void)?
    public var displayName: String { device.name }
    /// Format hardware actuel (valide après `start`).
    public private(set) var hardwareFormat: AVAudioFormat?

    public init(device: AudioInputDevice, channelPair: (left: Int, right: Int)) {
        self.device = device
        self.channelPair = channelPair
    }

    public func start(onSamples: @escaping ([Float], Double) -> Void) throws {
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw AudioSourceError.engineStartFailed("input node sans audio unit")
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw AudioSourceError.osStatus(status, "sélection du périphérique") }

        let format = engine.inputNode.inputFormat(forBus: 0)
        hardwareFormat = format
        let channelCount = Int(format.channelCount)
        guard channelCount > 0 else { throw AudioSourceError.engineStartFailed("périphérique sans canaux") }
        let left = min(channelPair.left, channelCount - 1)
        let right = min(channelPair.right, channelCount - 1)

        // format: nil = format natif (tous canaux, Float32 désentrelacé) ; le mixdown est fait ici.
        engine.inputNode.installTap(onBus: 0, bufferSize: 4800, format: nil) { [weak self] buffer, _ in
            self?.onRawBuffer?(buffer)
            guard let data = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            var mono = [Float](repeating: 0, count: frames)
            let leftData = data[left]
            let rightData = data[right]
            for i in 0..<frames { mono[i] = (leftData[i] + rightData[i]) * 0.5 }
            onSamples(mono, buffer.format.sampleRate)
        }

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            // Le moteur s'est arrêté tout seul (débranchement, changement de format).
            // Ne jamais désallouer le moteur depuis ce handler (deadlock documenté).
            DispatchQueue.main.async { self?.onFailure?("Périphérique audio déconnecté") }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw AudioSourceError.engineStartFailed(error.localizedDescription)
        }
    }

    public func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
