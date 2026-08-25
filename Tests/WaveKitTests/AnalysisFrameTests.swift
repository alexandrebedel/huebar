import Testing
@testable import WaveKit

@Test func silenceFrameIsZero() {
    #expect(AnalysisFrame.silence.rms == 0)
    #expect(AnalysisFrame.silence.beat == false)
}
