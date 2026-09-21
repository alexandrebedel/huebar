import Foundation
import Testing
@testable import HueKit
@testable import SyncKit
@testable import WaveKit

// Mode « Film d'horreur » : réagit au son d'un FILM (pas à un tempo), et surtout PAS aux
// dialogues — retour d'Alex sur le premier jet : « ça réagit bcp trop sur les dialogues ».

private let channels = (0..<5).map { SyncChannel(id: UInt8($0), x: Double($0) / 2 - 1) }

private let quietScene = AnalysisFrame(rms: 0.02, bass: 0.03, mid: 0.04, high: 0.02, beat: false)
private let loudScene = AnalysisFrame(rms: 0.5, bass: 0.7, mid: 0.6, high: 0.5, beat: false)
/// Impact de jump scare tel que mesuré dans l'analyseur (sub + bruit large bande).
private let impact = AnalysisFrame(rms: 0.5, bass: 1.0, mid: 0.18, high: 0.28, beat: true)

/// Déroule `seconds` de frames identiques à 50 Hz et renvoie toutes les sorties.
private func run(_ mapper: inout LightMapper, from start: Double, seconds: Double,
                 _ frame: AnalysisFrame) -> [[ChannelColor]] {
    (0..<Int(seconds / 0.02)).map { i in
        mapper.map(frame: frame, channels: channels, time: start + Double(i) * 0.02)
    }
}

/// Déroule une fixture de parole mesurée (éventuellement transformée) ; renvoie sorties et date de fin.
private func play(
    _ flat: [Double], in mapper: inout LightMapper, from start: Double = 0,
    transform: (Int, AnalysisFrame) -> AnalysisFrame = { _, frame in frame }
) -> (outputs: [[ChannelColor]], end: Double) {
    let frames = SpeechFixture.frames(flat)
    let outputs = frames.enumerated().map { index, values in
        let frame = AnalysisFrame(rms: values.rms, bass: values.bass, mid: values.mid, high: values.high,
                                  beat: index % 11 == 0) // l'analyseur voit des « beats » dans la parole
        return mapper.map(frame: transform(index, frame), channels: channels,
                          time: start + Double(index) * SpeechFixture.frameDuration)
    }
    return (outputs, start + Double(frames.count) * SpeechFixture.frameDuration)
}

private func isLightning(_ colors: [ChannelColor]) -> Bool {
    colors.contains { $0.green > 0.35 } // un éclair tire vers le blanc ; la lueur reste rouge
}

private func brightest(_ outputs: [[ChannelColor]]) -> Double {
    outputs.flatMap { $0.map { max($0.red, $0.green, $0.blue) } }.max() ?? 0
}

// MARK: - Dialogues

@Test func dialogueLightsNothingMoreThanSilence() {
    // LA garantie : sur de la vraie parole (forte, voix d'homme ; puis le pire cas 100 % voisé,
    // très fort), à froid comme en régime établi, aucun éclair et pas un iota de lueur en plus
    // de ce que fait le silence (la base qui vacille).
    var silent = LightMapper(mode: .horror)
    let ceiling = brightest(run(&silent, from: 0, seconds: 20, .silence))

    for fixture in [SpeechFixture.loudMaleDialogue, SpeechFixture.fullyVoicedVeryLoud] {
        var mapper = LightMapper(mode: .horror)
        var clock = 0.0
        for _ in 0..<3 { // 3 passes : démarrage à froid, puis référence apprise
            let (outputs, end) = play(fixture, in: &mapper, from: clock)
            clock = end
            #expect(!outputs.contains(where: isLightning))
            #expect(brightest(outputs) <= ceiling + 0.005)
        }
    }
}

@Test func rumbleUnderDialogueStillGlows() {
    // Un grondement qui PULSE (deux notes graves qui battent) sous le même dialogue : la pièce
    // doit rougeoyer nettement — sans éclair. (Un minimum strict ratait ce cas.)
    var mapper = LightMapper(mode: .horror)
    let (outputs, _) = play(SpeechFixture.loudMaleDialogue, in: &mapper) { index, frame in
        var frame = frame
        let beating = index % 3 == 0 ? 0.3 : 1.0 // creux du battement une frame sur trois
        frame.bass = min(1, frame.bass + beating)
        frame.rms = (frame.rms * frame.rms + 0.12 * 0.12).squareRoot()
        return frame
    }
    let settled = Array(outputs.dropFirst(60)) // la fenêtre « tenu » est remplie
    #expect(!outputs.contains(where: isLightning))
    #expect(brightest(settled) > 0.30)
    var silent = LightMapper(mode: .horror)
    #expect(brightest(settled) > 2 * brightest(run(&silent, from: 0, seconds: 8, .silence)))
}

@Test func jumpScareAfterDialogueFlashesTheWholeRoomWhite() {
    var mapper = LightMapper(mode: .horror)
    let (_, end) = play(SpeechFixture.loudMaleDialogue, in: &mapper) // la référence apprend le film
    let scare = run(&mapper, from: end, seconds: 0.3, impact)
    // Au pic : toute la pièce, très lumineuse, tirée vers le blanc (pas un rouge plus fort).
    let peak = scare.max { a, b in a.map(\.green).min()! < b.map(\.green).min()! }!
    for color in peak {
        #expect(color.red > 0.85)
        #expect(min(color.green, color.blue) > 0.6 * color.red)
    }
    // Et le dialogue qui reprend ensuite ne relance rien.
    let (after, _) = play(SpeechFixture.loudMaleDialogue, in: &mapper, from: end + 2)
    #expect(!after.dropFirst(50).contains(where: isLightning))
}

// MARK: - Sursauts, lueur, réglages

@Test func quietStaysDarkEvenAfterALoudPassage() {
    var mapper = LightMapper(mode: .horror)
    _ = run(&mapper, from: 0, seconds: 2, loudScene)
    let quiet = run(&mapper, from: 2, seconds: 6, quietScene)
    for colors in quiet.suffix(100) { // l'éclair et la lueur sont retombés
        for color in colors {
            #expect(color.red + color.green + color.blue < 0.35)
        }
    }
}

@Test func sustainedLoudnessNeverStrobes() {
    // Scène bruyante qui dure : un seul éclair au début, puis du rouge — jamais de
    // re-déclenchement en rafale (confort et photosensibilité).
    var mapper = LightMapper(mode: .horror)
    _ = run(&mapper, from: 0, seconds: 3, quietScene)
    let loud = run(&mapper, from: 3, seconds: 5, loudScene)
    #expect(loud.prefix(10).contains(where: isLightning))   // le sursaut d'entrée…
    #expect(!loud.dropFirst(75).contains(where: isLightning)) // …et plus rien après 1,5 s
}

@Test func noLightningDuringTheFirstSecondsOfTheMode() {
    // Au lancement de la sync, le premier son (logo, première réplique) n'est pas un sursaut.
    var mapper = LightMapper(mode: .horror)
    #expect(!run(&mapper, from: 0, seconds: 1, impact).contains(where: isLightning))
}

@Test func flashSliderAtZeroDisablesTheLightning() {
    var mapper = LightMapper(mode: .horror, tuning: SyncTuning(flash: 0))
    _ = run(&mapper, from: 0, seconds: 3, quietScene)
    #expect(!run(&mapper, from: 3, seconds: 0.5, impact).contains(where: isLightning))
}

@Test func defaultsToBloodRedsAndHonoursAThemeOtherwise() {
    // Un grondement tenu fait rougeoyer toute la pièce : de quoi juger la palette.
    let rumble = AnalysisFrame(rms: 0.13, bass: 1.0, mid: 0.02, high: 0, beat: false)
    var reds = LightMapper(mode: .horror)
    var ocean = LightMapper(mode: .horror, anchors: SyncTheme.ocean.hueAnchors)
    _ = run(&reds, from: 0, seconds: 1, rumble)
    _ = run(&ocean, from: 0, seconds: 1, rumble)
    let redRoom = run(&reds, from: 1, seconds: 4, rumble).flatMap { $0 }
    let blueRoom = run(&ocean, from: 1, seconds: 4, rumble).flatMap { $0 }
    #expect(redRoom.reduce(0) { $0 + $1.red } > 3 * redRoom.reduce(0) { $0 + $1.blue })
    #expect(blueRoom.reduce(0) { $0 + $1.blue } > 2 * blueRoom.reduce(0) { $0 + $1.red })
}

@Test func musicalBeatsAreIgnored() {
    // Un film n'a pas de tempo : les « beats » de l'analyseur ne font ni éclair ni BPM.
    var mapper = LightMapper(mode: .horror)
    _ = run(&mapper, from: 0, seconds: 3, loudScene)
    var outputs: [[ChannelColor]] = []
    for i in 0..<200 {
        var frame = loudScene
        frame.beat = i % 25 == 0
        outputs.append(mapper.map(frame: frame, channels: channels, time: 3 + Double(i) * 0.02))
    }
    #expect(mapper.estimatedBPM == nil)
    #expect(!outputs.contains(where: isLightning))
}

// MARK: - Filtre « tenu »

@Test func sustainTrackerKeepsWhatHoldsAndDropsWhatFalls() {
    var tracker = SustainTracker(window: 0.5, quantile: 0.25)
    // Fenêtre pas encore remplie : rien n'a « tenu ».
    #expect(tracker.push(1, at: 0) == 0)
    // Signal tenu : le niveau passe.
    var held = 0.0
    for i in 1...40 { held = tracker.push(0.8, at: Double(i) * 0.02) }
    #expect(held == 0.8)
    // Syllabes : 60 % du temps à 0.9, 40 % à 0 — le quart bas de la fenêtre est à zéro.
    var syllables = SustainTracker(window: 0.5, quantile: 0.25)
    var level = 1.0
    for i in 0..<100 { level = syllables.push(i % 10 < 6 ? 0.9 : 0, at: Double(i) * 0.02) }
    #expect(level == 0)
    // Grondement qui pulse : un creux bref (1 frame sur 5) ne l'efface pas…
    var pulsing = SustainTracker(window: 0.5, quantile: 0.25)
    for i in 0..<100 { level = pulsing.push(i % 5 == 0 ? 0.2 : 0.9, at: Double(i) * 0.02) }
    #expect(level == 0.9)
    // …alors qu'un minimum strict (quantile 0) tomberait dans le creux.
    var strict = SustainTracker(window: 0.5, quantile: 0)
    for i in 0..<100 { level = strict.push(i % 5 == 0 ? 0.2 : 0.9, at: Double(i) * 0.02) }
    #expect(level == 0.2)
}
