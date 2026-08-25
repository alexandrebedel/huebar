import AVFoundation
import CoreAudio
import Foundation

/// Capture tout l'audio joué par le Mac via un Core Audio process tap (macOS 14.2+).
/// Le premier `AudioDeviceStart` déclenche la demande « Enregistrement audio système ».
/// Un refus ne produit AUCUNE erreur : les buffers arrivent silencieux.
public final class SystemAudioTap: AudioSource {
    public var displayName: String { "Audio du Mac" }

    // Lu depuis la queue CoreAudio, muté depuis le MainActor : accès sous lock.
    private let callbackLock = NSLock()
    private var failureHandler: ((String) -> Void)?
    public var onFailure: ((String) -> Void)? {
        get { callbackLock.withLock { failureHandler } }
        set { callbackLock.withLock { failureHandler = newValue } }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var outputChangeListener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "huebar.systemtap")

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    public init() {}

    public func start(onSamples: @escaping ([Float], Double) -> Void) throws {
        // Tap global : « tout sauf ces processus » avec liste vide = tout l'audio système.
        // Ne PAS toucher isExclusive après coup (le flipper transforme la liste vide en
        // « seulement ces processus » = silence éternel).
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "HueBar"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &newTapID)
        guard status == noErr else { throw AudioSourceError.osStatus(status, "création du tap") }
        tapID = newTapID
        let sampleRate = tapSampleRate() ?? 48_000

        guard let outputUID = Self.defaultOutputDeviceUID() else {
            cleanup()
            throw AudioSourceError.deviceNotFound("sortie audio par défaut introuvable")
        }
        // L'aggregate DOIT contenir le vrai périphérique de sortie (sub-device ET main),
        // sinon il ne délivre aucun échantillon.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "HueBar Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var newAggregateID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &newAggregateID)
        guard status == noErr else {
            cleanup()
            throw AudioSourceError.osStatus(status, "création de l'aggregate")
        }
        aggregateID = newAggregateID

        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, inputData, _, _, _ in
            let allBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            // Une sortie par défaut duplex (interface USB, micro intégré d'un dock…) injecte
            // ses propres flux d'ENTRÉE dans l'aggregate, AVANT les flux du tap. On ne mixe
            // donc que le buffer du tap : le DERNIER buffer stéréo (format du tap) de la liste.
            let tapBuffer = allBuffers.last(where: { $0.mNumberChannels == 2 && $0.mData != nil })
                ?? allBuffers.last(where: { $0.mData != nil })
            guard let buffer = tapBuffer, let rawData = buffer.mData else { return }
            let channelCount = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channelCount
            guard frames > 0 else { return }
            let data = rawData.assumingMemoryBound(to: Float.self)
            var mono = [Float](repeating: 0, count: frames)
            if channelCount == 1 {
                for i in 0..<frames { mono[i] = data[i] }
            } else {
                for i in 0..<frames {
                    var sum: Float = 0
                    for c in 0..<channelCount { sum += data[i * channelCount + c] }
                    mono[i] = sum / Float(channelCount)
                }
            }
            onSamples(mono, sampleRate)
        }
        guard status == noErr else {
            cleanup()
            throw AudioSourceError.osStatus(status, "création du IOProc")
        }

        status = AudioDeviceStart(aggregateID, procID) // <- prompt TCC ici au premier lancement
        guard status == noErr else {
            cleanup()
            throw AudioSourceError.osStatus(status, "démarrage du tap")
        }

        // L'aggregate reste figé sur la sortie capturée au start : si l'utilisateur change
        // de sortie (AirPods, HDMI…), la capture gèlerait en silence. On remonte une erreur.
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onFailure?("Sortie audio par défaut modifiée — relancez la sync")
        }
        if AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, queue, listener) == noErr {
            outputChangeListener = listener
        }
    }

    public func stop() {
        cleanup()
    }

    private func cleanup() {
        if let outputChangeListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, queue, outputChangeListener)
            self.outputChangeListener = nil
        }
        if aggregateID != AudioObjectID(kAudioObjectUnknown) {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        procID = nil
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func tapSampleRate() -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd) == noErr else { return nil }
        return asbd.mSampleRate > 0 ? asbd.mSampleRate : nil
    }

    private static func defaultOutputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
