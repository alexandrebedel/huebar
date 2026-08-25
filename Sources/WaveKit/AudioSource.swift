import Foundation

/// Une source audio temps réel. Les callbacks arrivent sur une queue audio interne :
/// `onSamples(monoSamples, sampleRate)` — samples mono mixés, sampleRate courant du device.
public protocol AudioSource: AnyObject {
    var displayName: String { get }
    var onFailure: ((String) -> Void)? { get set }
    func start(onSamples: @escaping ([Float], Double) -> Void) throws
    func stop()
}

public enum AudioSourceError: Error, Equatable {
    case deviceNotFound(String)
    case osStatus(Int32, String)
    case engineStartFailed(String)
}
