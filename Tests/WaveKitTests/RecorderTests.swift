import AVFoundation
import Foundation
import Testing
@testable import WaveKit

private func makeBuffer(channels: AVAudioChannelCount, frames: AVAudioFrameCount,
                        sampleRate: Double) -> AVAudioPCMBuffer {
    // > 2 canaux exige un channel layout explicite (sinon AVAudioFormat renvoie nil).
    let format: AVAudioFormat = if channels <= 2 {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                      channels: channels, interleaved: false)!
    } else {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                      interleaved: false,
                      channelLayout: AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels))!)
    }
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<Int(channels) {
        let data = buffer.floatChannelData![channel]
        for i in 0..<Int(frames) {
            data[i] = 0.5 * Float(sin(2.0 * .pi * 440 * Double(i) / sampleRate))
        }
    }
    return buffer
}

@Test func recordsStereoPairToInt24Wav() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recorder = Recorder(directory: dir)

    // Device 4 canaux à 44.1 kHz : on enregistre la paire (2,3) au SR natif.
    try recorder.start(sampleRate: 44_100, filePrefix: "Test")
    let buffer = makeBuffer(channels: 4, frames: 4_410, sampleRate: 44_100)
    for _ in 0..<10 { recorder.append(from: buffer, left: 2, right: 3) }
    let url = try #require(recorder.currentFileURL)
    recorder.stop()

    let file = try AVAudioFile(forReading: url)
    #expect(url.pathExtension == "wav")
    #expect(file.fileFormat.sampleRate == 44_100)
    #expect(file.fileFormat.channelCount == 2)
    #expect(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int == 24)
    #expect(file.length == 44_100) // 10 × 4410 frames, rien de perdu

    // Le contenu n'est pas silencieux (la paire extraite porte bien le signal).
    let read = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_410)!
    try file.read(into: read)
    var peak: Float = 0
    for i in 0..<Int(read.frameLength) { peak = max(peak, abs(read.floatChannelData![0][i])) }
    #expect(peak > 0.4)
}

@Test func filenameIsTimestampedAndColonFree() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let recorder = Recorder(directory: dir)
    try recorder.start(sampleRate: 48_000, filePrefix: "PX5")
    let name = try #require(recorder.currentFileURL?.lastPathComponent)
    recorder.stop()
    #expect(name.hasPrefix("PX5 "))
    #expect(name.hasSuffix(".wav"))
    #expect(!name.contains(":") && !name.contains("/"))
}

@Test func stopWithoutStartIsHarmless() {
    let recorder = Recorder(directory: FileManager.default.temporaryDirectory)
    recorder.stop()
    #expect(recorder.currentFileURL == nil)
}
