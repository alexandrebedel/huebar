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

@Test func steadyMusicReachesUsefulBrightness() {
    // Retour utilisateur : « intensité très faible en mode musique ». Avec un signal
    // soutenu, chaque channel doit dépasser un niveau clairement visible.
    for mode in SyncMode.allCases {
        var mapper = LightMapper(mode: mode)
        var colors: [ChannelColor] = []
        for i in 0..<150 {
            colors = mapper.map(frame: frame(rms: 0.3, bass: 0.5), channels: channels, time: Double(i) * 0.02)
        }
        for color in colors {
            #expect(color.red + color.green + color.blue > 0.5, "\(mode) trop sombre")
        }
    }
}

@Test func colorTransitionsAreSmoothAcrossBeats() {
    // Retour utilisateur : « pas smooth du tout sur les changements de couleur ».
    // Même au beat (saut de teinte + flash), la variation par frame reste bornée.
    var mapper = LightMapper(mode: .club)
    var time = 0.0
    var previous = mapper.map(frame: frame(), channels: channels, time: time)
    for i in 1..<100 {
        time += 0.02
        let next = mapper.map(frame: frame(beat: i % 10 == 0), channels: channels, time: time)
        for (a, b) in zip(previous, next) {
            #expect(abs(a.red - b.red) < 0.45)
            #expect(abs(a.green - b.green) < 0.45)
            #expect(abs(a.blue - b.blue) < 0.45)
        }
        previous = next
    }
}

@Test func sunsetThemeStaysWarm() {
    // Le thème contraint les teintes : en Sunset, le rouge doit dominer le bleu
    // en moyenne, malgré la rotation de teinte et les beats.
    var mapper = LightMapper(mode: .club, theme: .sunset)
    var totalRed = 0.0
    var totalBlue = 0.0
    var time = 0.0
    for i in 0..<300 {
        time += 0.02
        let colors = mapper.map(frame: frame(beat: i % 10 == 0), channels: channels, time: time)
        for color in colors {
            totalRed += color.red
            totalBlue += color.blue
        }
    }
    #expect(totalRed > totalBlue * 1.3)
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
