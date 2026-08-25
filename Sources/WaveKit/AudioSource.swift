import Foundation

/// Une source audio temps réel. Les callbacks arrivent sur une queue audio interne :
/// `onSamples(monoSamples, sampleRate)` — samples mono mixés, sampleRate courant du device.
public protocol AudioSource: AnyObject {
    var displayName: String { get }
    // @Sendable est structurel : ces callbacks sont invoqués depuis les threads audio
    // (HAL IO, tap AVAudioEngine). Sans lui, une closure créée dans un contexte @MainActor
    // hérite de cette isolation et le runtime Swift 6 trap au premier buffer réel.
    var onFailure: (@Sendable (String) -> Void)? { get set }
    func start(onSamples: @escaping @Sendable ([Float], Double) -> Void) throws
    func stop()
}

public enum AudioSourceError: Error, Equatable {
    case deviceNotFound(String)
    case osStatus(Int32, String)
    case engineStartFailed(String)
}
