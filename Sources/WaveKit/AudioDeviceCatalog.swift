import CoreAudio
import Foundation

/// Un périphérique d'entrée CoreAudio, avec ses canaux nommés.
public struct AudioInputDevice: Sendable, Equatable, Identifiable {
    public var id: AudioDeviceID
    public var uid: String
    public var name: String
    public var channelCount: Int
    /// Noms de canaux (1 par canal, fallback "Canal n").
    public var channelNames: [String]

    /// Paires de canaux proposables (0-based) avec libellé, ex. (8, 9, "9-10 · Master L/R").
    public var channelPairs: [(left: Int, right: Int, label: String)] {
        stride(from: 0, to: channelCount - 1, by: 2).map { left in
            let label = "\(left + 1)-\(left + 2) · \(channelNames[left])/\(channelNames[left + 1])"
            return (left, left + 1, label)
        }
    }

    public static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.uid == rhs.uid && lhs.channelCount == rhs.channelCount
    }
}

/// Énumération des périphériques d'entrée via l'API C CoreAudio.
public enum AudioDeviceCatalog {
    public static func inputDevices() -> [AudioInputDevice] {
        deviceIDs().compactMap { deviceID in
            let inputChannels = channelCount(deviceID, scope: kAudioObjectPropertyScopeInput)
            guard inputChannels > 0 else { return nil }
            guard let uid: String = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
                  let name: String = stringProperty(deviceID, kAudioDevicePropertyDeviceNameCFString)
            else { return nil }
            let names = (1...inputChannels).map { channel in
                channelName(deviceID, channel: UInt32(channel)) ?? defaultChannelLabel(deviceName: name, channel: channel)
            }
            return AudioInputDevice(id: deviceID, uid: uid, name: name,
                                    channelCount: inputChannels, channelNames: names)
        }
    }

    public static func device(uid: String) -> AudioInputDevice? {
        inputDevices().first { $0.uid == uid }
    }

    /// La Xone:PX5 porte son master sur USB 9/10 (0-based 8/9) quand le switch arrière est sur MST.
    public static func defaultPairIndex(for device: AudioInputDevice) -> Int {
        if device.name.localizedCaseInsensitiveContains("PX5"), device.channelCount >= 10 {
            return 4 // paire 9-10
        }
        return 0
    }

    private static func defaultChannelLabel(deviceName: String, channel: Int) -> String {
        if deviceName.localizedCaseInsensitiveContains("PX5") {
            switch channel {
            case 1...8: return "CH\((channel + 1) / 2) \(channel.isMultiple(of: 2) ? "R" : "L")"
            case 9: return "Master L"
            case 10: return "Master R"
            default: break
            }
        }
        return "Canal \(channel)"
    }

    // MARK: - Plomberie CoreAudio

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
        else { return [] }
        return ids
    }

    private static func channelCount(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let listPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { listPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, listPointer) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(listPointer.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func channelName(_ deviceID: AudioDeviceID, channel: UInt32) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyElementName,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: channel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else { return nil }
        let name = value?.takeRetainedValue() as String?
        return (name?.isEmpty ?? true) ? nil : name
    }
}
