import Testing
@testable import HueKit
@testable import SyncKit
@testable import WaveKit

private let channels = [
    SyncChannel(id: 0, x: -1.0),
    SyncChannel(id: 1, x: 0.0),
    SyncChannel(id: 2, x: 1.0),
]

private func frame(rms: Double = 0.3, bass: Double = 0.4, mid: Double = 0.3,
                   high: Double = 0.2, beat: Bool = false) -> AnalysisFrame {
    AnalysisFrame(rms: rms, bass: bass, mid: mid, high: high, beat: beat)
}

@Test func producesOneColorPerChannel() {
    var mapper = LightMapper(mode: .club)
    let colors = mapper.map(frame: frame(), channels: channels, time: 0)
    #expect(colors.map(\.channel) == [0, 1, 2])
}

@Test func outputsStayInRangeUnderExtremes() {
    for mode in SyncMode.allCases {
        var mapper = LightMapper(mode: mode)
        var time = 0.0
        for extreme in [frame(rms: 0, bass: 0, mid: 0, high: 0),
                        frame(rms: 5, bass: 5, mid: 5, high: 5, beat: true)] {
            for _ in 0..<100 {
                for color in mapper.map(frame: extreme, channels: channels, time: time) {
                    #expect(color.red >= 0 && color.red <= 1)
                    #expect(color.green >= 0 && color.green <= 1)
                    #expect(color.blue >= 0 && color.blue <= 1)
                }
                time += 0.02
            }
        }
    }
}

@Test func clubBeatIsBrighterThanNoBeat() {
    var withBeat = LightMapper(mode: .club)
    var withoutBeat = LightMapper(mode: .club)
    _ = withBeat.map(frame: frame(), channels: channels, time: 0)
    _ = withoutBeat.map(frame: frame(), channels: channels, time: 0)
    let beatColors = withBeat.map(frame: frame(beat: true), channels: channels, time: 0.02)
    let calmColors = withoutBeat.map(frame: frame(beat: false), channels: channels, time: 0.02)
    func luminance(_ colors: [ChannelColor]) -> Double {
        colors.reduce(0) { $0 + $1.red + $1.green + $1.blue }
    }
    #expect(luminance(beatColors) > luminance(calmColors))
}

@Test func chillDriftsSlowly() {
    var mapper = LightMapper(mode: .chill)
    let first = mapper.map(frame: frame(), channels: channels, time: 0)
    let second = mapper.map(frame: frame(), channels: channels, time: 0.02)
    for (a, b) in zip(first, second) {
        #expect(abs(a.red - b.red) < 0.1)
        #expect(abs(a.green - b.green) < 0.1)
        #expect(abs(a.blue - b.blue) < 0.1)
    }
}

@Test func silenceIsDimInBothModes() {
    for mode in SyncMode.allCases {
        var mapper = LightMapper(mode: mode)
        var colors: [ChannelColor] = []
        for i in 0..<50 {
            colors = mapper.map(frame: .silence, channels: channels, time: Double(i) * 0.02)
        }
        for color in colors {
            #expect(color.red + color.green + color.blue < 0.9)
        }
    }
}
