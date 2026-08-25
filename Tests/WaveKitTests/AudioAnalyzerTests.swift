import Foundation
import Testing
@testable import WaveKit

private let sampleRate = 48_000.0

private func sine(frequency: Double, amplitude: Float, frames: Int, startFrame: Int = 0) -> [Float] {
    (0..<frames).map { i in
        amplitude * Float(sin(2.0 * .pi * frequency * Double(startFrame + i) / sampleRate))
    }
}

/// Nourrit l'analyzer par chunks de 512 frames et collecte toutes les frames d'analyse.
private func analyzeAll(_ samples: [Float]) -> [AnalysisFrame] {
    let analyzer = AudioAnalyzer(sampleRate: sampleRate)
    var frames: [AnalysisFrame] = []
    var index = 0
    while index < samples.count {
        let end = min(index + 512, samples.count)
        frames.append(contentsOf: analyzer.processAll(samples: Array(samples[index..<end])))
        index = end
    }
    return frames
}

@Test func silenceIsQuietAndBeatless() {
    let frames = analyzeAll([Float](repeating: 0, count: 48_000))
    #expect(!frames.isEmpty)
    #expect(frames.allSatisfy { $0.rms < 0.001 && !$0.beat })
}

@Test func bassSineDominatesLowBand() {
    let frames = analyzeAll(sine(frequency: 60, amplitude: 0.8, frames: 48_000))
    let stable = frames.dropFirst(5)
    #expect(!stable.isEmpty)
    for frame in stable {
        #expect(frame.bass > frame.mid)
        #expect(frame.bass > frame.high)
    }
}

@Test func highSineDominatesHighBand() {
    let frames = analyzeAll(sine(frequency: 8_000, amplitude: 0.8, frames: 48_000))
    let stable = frames.dropFirst(5)
    for frame in stable {
        #expect(frame.high > frame.bass)
    }
}

@Test func kickPatternProducesBeats() {
    // 3 s : kick de 100 ms de sinus 60 Hz toutes les 500 ms (≈ 120 BPM), silence entre.
    var samples: [Float] = []
    for _ in 0..<6 {
        samples.append(contentsOf: sine(frequency: 60, amplitude: 0.9, frames: 4_800))
        samples.append(contentsOf: [Float](repeating: 0, count: 19_200))
    }
    let beats = analyzeAll(samples).filter(\.beat).count
    #expect(beats >= 3 && beats <= 10) // ~6 attaques, marges pour l'attaque/fenêtrage
}

@Test func continuousBassDoesNotSpamBeats() {
    let beats = analyzeAll(sine(frequency: 60, amplitude: 0.8, frames: 96_000)).filter(\.beat).count
    #expect(beats <= 2) // l'attaque initiale au plus — pas de beats sur un niveau constant
}

@Test func kicksOverSustainedBassAreStillDetected() {
    // Nappe de basse continue + kicks par-dessus : un détecteur par niveau ratait les
    // kicks (la moyenne montait avec la nappe), le flux spectral capte les transitoires.
    var samples = sine(frequency: 55, amplitude: 0.25, frames: 144_000)
    for beatIndex in 0..<6 {
        let start = beatIndex * 24_000
        let kick = sine(frequency: 90, amplitude: 0.9, frames: 4_800, startFrame: start)
        for (offset, value) in kick.enumerated() { samples[start + offset] += value }
    }
    let beats = analyzeAll(samples).filter(\.beat).count
    #expect(beats >= 3 && beats <= 12)
}
