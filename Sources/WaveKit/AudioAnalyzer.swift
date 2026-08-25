import Accelerate
import Foundation

/// Analyse temps réel : fenêtres de 1024 échantillons (Hann + FFT),
/// énergie par bandes (basses < 150 Hz, mids 150–2000 Hz, aigus > 2000 Hz),
/// détection de beat par flux d'énergie des basses contre une moyenne glissante.
/// Non thread-safe : à utiliser depuis la queue audio uniquement.
public final class AudioAnalyzer {
    private static let windowSize = 1024
    private static let log2n = vDSP_Length(10)

    private let sampleRate: Double
    private let fftSetup: FFTSetup
    private var window = [Float](repeating: 0, count: windowSize)
    private var pending: [Float] = []

    private var bassHistory: [Double] = []
    private var framesSinceBeat = Int.max

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
        pending.reserveCapacity(Self.windowSize * 4)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Traite un chunk arbitraire ; retourne la dernière frame d'analyse complète (ou nil).
    public func process(samples: [Float]) -> AnalysisFrame? {
        processAll(samples: samples).last
    }

    /// Comme `process` mais retourne toutes les frames produites par ce chunk (utile aux tests).
    public func processAll(samples: [Float]) -> [AnalysisFrame] {
        pending.append(contentsOf: samples)
        var frames: [AnalysisFrame] = []
        while pending.count >= Self.windowSize {
            frames.append(analyzeWindow(Array(pending[0..<Self.windowSize])))
            pending.removeFirst(Self.windowSize)
        }
        return frames
    }

    private func analyzeWindow(_ input: [Float]) -> AnalysisFrame {
        var rms: Float = 0
        vDSP_rmsqv(input, 1, &rms, vDSP_Length(Self.windowSize))

        var windowed = [Float](repeating: 0, count: Self.windowSize)
        vDSP_vmul(input, 1, window, 1, &windowed, 1, vDSP_Length(Self.windowSize))

        // FFT réelle in-place (format split complex packé).
        let half = Self.windowSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        let binWidth = sampleRate / Double(Self.windowSize)
        func bandLevel(_ low: Double, _ high: Double, gain: Double) -> Double {
            let first = max(1, Int(low / binWidth))
            let last = min(half - 1, Int(high / binWidth))
            guard last >= first else { return 0 }
            var sum: Float = 0
            for bin in first...last { sum += magnitudes[bin] }
            let mean = Double(sum) / Double(last - first + 1)
            // sqrt ramène en amplitude ; normalisation empirique vers ~0...1 pour de la musique.
            return min(1, sqrt(mean) / 1024 * gain)
        }

        let bass = bandLevel(20, 150, gain: 8)
        let mid = bandLevel(150, 2_000, gain: 12)
        let high = bandLevel(2_000, 16_000, gain: 20)

        // Beat : flux des basses vs moyenne glissante (~1 s), avec réfractaire de 7 frames (~150 ms).
        let average = bassHistory.isEmpty ? 0 : bassHistory.reduce(0, +) / Double(bassHistory.count)
        framesSinceBeat = framesSinceBeat == Int.max ? Int.max : framesSinceBeat + 1
        var beat = false
        if bass > 0.05, bass > average * 1.5, framesSinceBeat > 7 || framesSinceBeat == Int.max {
            beat = true
            framesSinceBeat = 0
        }
        bassHistory.append(bass)
        if bassHistory.count > 46 { bassHistory.removeFirst() }

        return AnalysisFrame(rms: Double(rms), bass: bass, mid: mid, high: high, beat: beat)
    }
}
