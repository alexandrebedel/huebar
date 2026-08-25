import Foundation

/// Résultat d'une fenêtre d'analyse audio (~21 ms à 48 kHz).
public struct AnalysisFrame: Sendable, Equatable {
    public var rms: Double
    public var bass: Double
    public var mid: Double
    public var high: Double
    public var beat: Bool

    public init(rms: Double, bass: Double, mid: Double, high: Double, beat: Bool) {
        self.rms = rms
        self.bass = bass
        self.mid = mid
        self.high = high
        self.beat = beat
    }

    public static let silence = AnalysisFrame(rms: 0, bass: 0, mid: 0, high: 0, beat: false)
}
