import Foundation
import HueKit
import WaveKit

/// Channel de la zone Entertainment avec sa position latérale (-1 gauche ... 1 droite).
public struct SyncChannel: Sendable, Equatable {
    public var id: UInt8
    public var x: Double

    public init(id: UInt8, x: Double) {
        self.id = id
        self.x = x
    }
}

/// Suit le maximum récent d'un signal (montée instantanée, décroissance lente) pour le
/// ramener dans 0...1 quel que soit le volume de la source — le principe du `mel_gain`
/// de LedFx. Sans ça, un morceau calme est éteint et un morceau fort sature.
struct AutoGain: Sendable {
    private var peak = LightMapper.Tuning.gainFloor

    mutating func normalize(_ value: Double, dt: Double) -> Double {
        if value > peak {
            peak = value
        } else {
            peak += (value - peak) * min(1, dt / LightMapper.Tuning.gainDecaySeconds)
        }
        peak = max(peak, LightMapper.Tuning.gainFloor)
        return min(1, value / peak)
    }
}

/// Niveau qu'un signal TIENT sur une fenêtre de temps (quantile bas glissant ; 0 = minimum
/// strict) : ce qui dure passe, ce qui retombe est effacé. C'est ce qui sépare un grondement
/// d'une voix grave, dont le fondamental pèse autant dans la bande des basses mais retombe
/// entre les syllabes. Un quantile (plutôt que le minimum) tolère un grondement qui pulse.
struct SustainTracker: Sendable {
    private let window: Double
    private let quantile: Double
    private var samples: [(time: Double, value: Double)] = []
    private var startTime: Double?

    init(window: Double, quantile: Double) {
        self.window = window
        self.quantile = quantile
    }

    mutating func push(_ value: Double, at time: Double) -> Double {
        if startTime == nil { startTime = time }
        samples.append((time, value))
        samples.removeAll { $0.time <= time - window }
        // Tant que la fenêtre n'est pas remplie, rien n'a encore « tenu ».
        guard let startTime, time - startTime >= window else { return 0 }
        let sorted = samples.map(\.value).sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * quantile))]
    }
}

/// Transforme les frames d'analyse en couleurs par channel. À état (déterministe pour un
/// même enchaînement d'appels) : palette distribuée entre les lampes et tournée sur les
/// beats, chaque lampe suivant sa propre bande (basses / mids / aigus), tempo estimé
/// pour accentuer les temps forts, lissages.
public struct LightMapper {
    /// Toutes les constantes de rendu — le « feel » de la sync se règle ici.
    enum Tuning {
        /// Sous ~0.5 en linéaire les Hue paraissent éteintes : levée perceptuelle.
        static let brightnessGamma = 0.6

        // Auto-gain : chaque bande est normalisée par son pic récent.
        static let gainDecaySeconds = 2.5
        static let gainFloor = 0.03          // pas d'amplification du bruit de fond (le gate
                                             // de silence gère le vrai silence)
        static let silenceRMS = 0.004        // en dessous : silence, tout au repos

        // Lissage des bandes normalisées (1/s) puis de la sortie (EMA asymétrique, s).
        static let clubBandSmoothingRate = 9.0
        static let chillBandSmoothingRate = 3.0
        static let clubAttack = 0.12, clubRelease = 0.30
        static let chillAttack = 0.08, chillRelease = 0.35

        // Club.
        static let clubBaseBrightness = 0.10
        static let clubBandGain = 0.80       // la bande propre à la lampe
        static let clubRMSGain = 0.25        // + un peu d'énergie globale
        static let clubFlashDecayPerSecond = 4.0
        static let clubOffBeatFlash = 0.4    // les lampes « hors temps » flashent moins
        static let downbeatBoost = 1.35
        static let clubMinSaturation = 0.55
        static let clubHighDesaturation = 0.5
        static let clubHueSpread = 0.12      // Spectre : écart de teinte entre lampes
        static let clubHueDriftPerSecond = 0.02
        static let clubWarmthPullPerSecond = 0.08

        // Chill.
        static let chillBaseBrightness = 0.12
        static let chillRMSGain = 0.65
        static let chillBandGain = 0.35
        static let chillSaturation = 0.65
        static let chillHueSpread = 0.06
        static let chillHueDriftPerSecond = 0.015
        static let chillWarmthPullPerSecond = 0.25
        static let chillRotationSeconds = 10.0

        // Film d'horreur : la pièce reste sombre, rougeoie sur ce qui MENACE et éclate en
        // éclair blanc sur les sursauts — sans jamais suivre les dialogues. Tout est mesuré
        // sur le signal BRUT (pas d'auto-gain : il finit par normaliser… les voix elles-mêmes).
        // Calibré sur de la vraie parole passée dans l'analyseur : une voix d'homme pèse
        // 0.40 (p90) à 0.58 (max) dans la bande des basses, autant qu'un grondement modéré.
        static let horrorBaseBrightness = 0.035
        static let horrorLevelSmoothingRate = 5.0    // 1/s, lissage du niveau brut
        static let horrorSaturation = 0.95
        static let horrorFlickerDepth = 0.25         // vacillement d'inquiétude, par lampe
        static let horrorRotationSeconds = 20.0
        static let horrorAttack = 0.03, horrorRelease = 0.45
        /// Rouges sang et un violet profond ; remplacés par les ancres d'un thème s'il y en a un.
        static let horrorDefaultAnchors = [0.0, 0.97, 0.02, 0.80]

        // Référence « niveau de programme » ≈ dialogues forts : monte en ~10 s, redescend en
        // ~30 s, et les pauses (sous une fraction de la référence) ne l'abaissent pas — sinon
        // chaque reprise de parole après un silence ressemblerait à un sursaut. Elle DÉMARRE
        // haut : tant qu'elle n'a pas appris le film, un dialogue fort ne doit rien allumer.
        static let horrorProgramInitial = 0.10
        static let horrorProgramFloor = 0.04
        static let horrorProgramRiseSeconds = 10.0
        static let horrorProgramFallSeconds = 30.0
        static let horrorProgramPauseFraction = 0.2

        // Tension : niveau lissé nettement AU-DESSUS du programme. Mesuré : en régime établi
        // la parole (homme, femme, 100 % voisée, de 0.07 à 0.16) plafonne à 1.17× le programme.
        static let horrorTensionKneeLow = 1.8, horrorTensionKneeHigh = 5.0
        static let horrorTensionGain = 0.50
        // Grondement : basses « pures » (une voix a toujours des mids proportionnels à ses
        // basses, un grondement non) et TENUES. Mesuré sur basses − 1.3 × mids, quantile 25 %
        // sur 0.6 s : parole normale ≤ 0.002, pire cas (100 % voisé, fort) 0.147 ; un drone qui
        // pulse garde 0.51 seul et 0.40 SOUS un dialogue (le minimum strict le ratait).
        static let horrorVoiceMidFactor = 1.3
        static let horrorRumbleSustainSeconds = 0.6
        static let horrorRumbleHeldQuantile = 0.25
        static let horrorRumbleGateLow = 0.20, horrorRumbleGateHigh = 0.80
        static let horrorRumbleGain = 0.45
        static let horrorRumbleOnStridentLamps = 0.6 // les lampes « aigus » grondent moins
        // Stridence : aigus tenus (cordes, larsen) — les sifflantes de la parole sont trop brèves.
        static let horrorStridenceSustainSeconds = 0.35
        static let horrorStridenceHeldQuantile = 0.0 // minimum strict : une sifflante ne tient pas
        static let horrorStridenceGateLow = 0.12, horrorStridenceGateHigh = 0.50
        static let horrorStridenceGain = 0.35

        // Sursaut (jump scare) : TRÈS au-dessus du programme ET bond net au-dessus de
        // l'ambiance de la dernière seconde. L'ambiance rattrape le sursaut d'un coup : une
        // scène bruyante qui dure ne re-déclenche pas (jamais de stroboscope, ~2 Hz max).
        // Mesuré : frame par frame, la parole ne dépasse jamais 1.5× le niveau de programme.
        static let horrorShockOverProgram = 3.0      // × le niveau de programme pour déclencher
        static let horrorShockFullOverProgram = 5.0  // × pour un éclair à pleine force
        static let horrorShockMinStrength = 0.5
        static let horrorShockRatio = 2.4            // niveau instantané / ambiance rapide
        static let horrorShockRefractory = 0.45      // s
        static let horrorShockWarmup = 2.0           // s sans éclair au démarrage du mode
        static let horrorShockAmbientCatchUp = 0.8
        static let horrorAmbientRiseSeconds = 3.0
        static let horrorAmbientFallSeconds = 1.2
        static let horrorFlashDecayPerSecond = 2.2   // extinction ~450 ms
        static let horrorFlashDesaturation = 0.9     // l'éclair tire vers le blanc
        static let horrorFlashReference = 0.30       // réglage « Flash » par défaut = éclair plein

        // Chaleur du son (centroïde) → teinte de base, le long de l'axe thermique
        // bleu → violet → rouge/orange (jamais par le vert). Sans effet avec un thème.
        static let coldHue = 0.58
        static let warmHueSpan = 0.45
        static let warmthSmoothingRate = 2.0

        // Tempo : intervalles entre beats plausibles et fenêtre de médiane.
        static let minBeatInterval = 0.30    // 200 BPM
        static let maxBeatInterval = 1.00    // 60 BPM
        static let tempoHistory = 8
    }

    /// Bande suivie par une lampe : voisines différentes pour que la pièce « respire »
    /// à plusieurs vitesses (LedFx Energy : basses / mids / aigus en zones distinctes).
    enum Role: Int, CaseIterable { case bass, mid, high }

    private let mode: SyncMode
    /// Ancres de teinte imposées (nil = spectre libre), modifiables en cours de route.
    public var anchors: [Double]?
    /// Réglages utilisateur, modifiables en cours de route sans reset de l'état.
    public var tuning: SyncTuning
    /// Tempo estimé (médiane des intervalles entre beats), nil tant que rien n'est stable.
    public private(set) var estimatedBPM: Double?

    private var baseHue = 0.62 // départ bleu nuit
    private var flash = 0.0
    private var lastTime: Double?
    private var smoothedWarmth = 0.5
    private var gains = (rms: AutoGain(), bass: AutoGain(), mid: AutoGain(), high: AutoGain())

    // Film d'horreur (état propre au mode, sur le signal brut).
    private var programRMS = Tuning.horrorProgramInitial
    private var ambientRMS = 0.0
    private var horrorLevel = 0.0
    private var sustainedBass = SustainTracker(
        window: Tuning.horrorRumbleSustainSeconds, quantile: Tuning.horrorRumbleHeldQuantile)
    private var sustainedHigh = SustainTracker(
        window: Tuning.horrorStridenceSustainSeconds, quantile: Tuning.horrorStridenceHeldQuantile)
    private var horrorStartTime: Double?
    private var lastShockTime: Double?
    private var smoothedBands: [Role: Double] = [.bass: 0, .mid: 0, .high: 0]
    private var smoothedRMS = 0.0
    private var smoothedOutput: [UInt8: (red: Double, green: Double, blue: Double)] = [:]

    // Palette et tempo.
    private var rotation = 0
    private var rotationClock = 0.0
    private var beatIndex = 0               // position dans la mesure (0 = temps fort)
    private var lastBeatTime: Double?
    private var beatIntervals: [Double] = []

    public init(mode: SyncMode, anchors: [Double]? = nil, tuning: SyncTuning = .default) {
        self.mode = mode
        self.anchors = anchors
        self.tuning = tuning
    }

    public mutating func map(frame: AnalysisFrame, channels: [SyncChannel], time: Double) -> [ChannelColor] {
        let dt = lastTime.map { max(0, min(0.2, time - $0)) } ?? 0.02
        lastTime = time
        let silent = frame.rms < Tuning.silenceRMS

        // Normalisation puis lissage des bandes : la dynamique devient relative au morceau.
        let normalized: (rms: Double, bass: Double, mid: Double, high: Double) = silent
            ? (0, 0, 0, 0)
            : (gains.rms.normalize(frame.rms, dt: dt),
               gains.bass.normalize(frame.bass, dt: dt),
               gains.mid.normalize(frame.mid, dt: dt),
               gains.high.normalize(frame.high, dt: dt))
        let bandRate = switch mode {
        case .club: Tuning.clubBandSmoothingRate
        case .chill: Tuning.chillBandSmoothingRate
        case .horror: Tuning.horrorLevelSmoothingRate // inutilisé : le mode travaille sur le brut
        }
        let bandStep = min(1, dt * bandRate)
        smoothedRMS += (normalized.rms - smoothedRMS) * bandStep
        smoothedBands[.bass]! += (normalized.bass - smoothedBands[.bass]!) * bandStep
        smoothedBands[.mid]! += (normalized.mid - smoothedBands[.mid]!) * bandStep
        smoothedBands[.high]! += (normalized.high - smoothedBands[.high]!) * bandStep
        smoothedWarmth += (frame.warmth - smoothedWarmth) * min(1, dt * Tuning.warmthSmoothingRate)

        if frame.beat, !silent, mode != .horror {
            registerBeat(at: time)
        }

        let targets = switch mode {
        case .club: mapClub(frame: frame, channels: channels, dt: dt)
        case .chill: mapChill(channels: channels, dt: dt)
        case .horror: mapHorror(frame: frame, channels: channels, dt: dt, time: time)
        }
        // Lissage de sortie : les sauts de teinte/flash deviennent des transitions,
        // sans tuer l'attaque (montée plus rapide que la descente).
        return targets.map { smoothedColor($0, dt: dt) }
    }

    // MARK: - Modes

    private mutating func mapClub(frame: AnalysisFrame, channels: [SyncChannel], dt: Double) -> [ChannelColor] {
        baseHue = (baseHue + dt * Tuning.clubHueDriftPerSecond).truncatingRemainder(dividingBy: 1)
        pullHueTowardWarmth(dt: dt, rate: Tuning.clubWarmthPullPerSecond)
        flash = max(0, flash - dt * Tuning.clubFlashDecayPerSecond)

        let hues = paletteHues(count: channels.count, spread: Tuning.clubHueSpread)
        let saturation = max(Tuning.clubMinSaturation,
                             1 - min(0.4, smoothedBands[.high]! * Tuning.clubHighDesaturation))
        let ordered = Self.orderedIndices(channels)

        return channels.indices.map { index in
            let slot = ordered[index]
            let role = Role.allCases[slot % Role.allCases.count]
            // Les lampes alternent au rythme des beats : une moitié flashe plein, l'autre moins.
            let onBeat = (slot + beatIndex) % 2 == 0
            let flashWeight = onBeat ? 1.0 : Tuning.clubOffBeatFlash
            let energy = min(1, (smoothedBands[role]! * Tuning.clubBandGain
                + smoothedRMS * Tuning.clubRMSGain) * tuning.sensitivity)
            let brightness = min(1, Tuning.clubBaseBrightness + energy * (1 - Tuning.clubBaseBrightness)
                + flash * tuning.flash * flashWeight)
            return color(channel: channels[index].id, hue: hues[(slot + rotation) % hues.count],
                         saturation: saturation, value: brightness)
        }
    }

    private mutating func mapChill(channels: [SyncChannel], dt: Double) -> [ChannelColor] {
        // Dérive lente pour la vie ; la chaleur du son pilote la teinte de fond ;
        // la palette tourne doucement entre les lampes (pas sur les beats).
        baseHue = (baseHue + dt * Tuning.chillHueDriftPerSecond).truncatingRemainder(dividingBy: 1)
        pullHueTowardWarmth(dt: dt, rate: Tuning.chillWarmthPullPerSecond)
        rotationClock += dt
        if rotationClock >= Tuning.chillRotationSeconds {
            rotationClock = 0
            rotation += 1
        }

        let hues = paletteHues(count: channels.count, spread: Tuning.chillHueSpread)
        let ordered = Self.orderedIndices(channels)

        return channels.indices.map { index in
            let slot = ordered[index]
            let role = Role.allCases[slot % Role.allCases.count]
            // Respire avec le morceau : énergie globale + la bande propre à la lampe.
            let energy = min(1, (smoothedRMS * Tuning.chillRMSGain
                + smoothedBands[role]! * Tuning.chillBandGain) * tuning.sensitivity)
            let brightness = min(1, Tuning.chillBaseBrightness + energy * (1 - Tuning.chillBaseBrightness))
            return color(channel: channels[index].id, hue: hues[(slot + rotation) % hues.count],
                         saturation: Tuning.chillSaturation, value: brightness)
        }
    }

    private mutating func mapHorror(
        frame: AnalysisFrame, channels: [SyncChannel], dt: Double, time: Double
    ) -> [ChannelColor] {
        let rms = frame.rms
        if horrorStartTime == nil { horrorStartTime = time }

        // Sursaut : très au-dessus du niveau de programme ET bond net sur la dernière seconde.
        let overProgram = rms / programRMS
        let ambience = max(ambientRMS, Tuning.silenceRMS)
        if overProgram >= Tuning.horrorShockOverProgram, rms > ambience * Tuning.horrorShockRatio,
           time - (horrorStartTime ?? time) >= Tuning.horrorShockWarmup,
           time - (lastShockTime ?? -.infinity) > Tuning.horrorShockRefractory {
            let span = Tuning.horrorShockFullOverProgram - Tuning.horrorShockOverProgram
            let force = min(1, (overProgram - Tuning.horrorShockOverProgram) / span)
            flash = Tuning.horrorShockMinStrength + (1 - Tuning.horrorShockMinStrength) * force
            lastShockTime = time
            ambientRMS = max(ambientRMS, rms * Tuning.horrorShockAmbientCatchUp)
        }
        let ambientTau = rms > ambientRMS ? Tuning.horrorAmbientRiseSeconds : Tuning.horrorAmbientFallSeconds
        ambientRMS += (rms - ambientRMS) * min(1, dt / ambientTau)

        // Niveau de programme : les pauses ne comptent pas, la montée est lente, la descente très lente.
        if rms >= programRMS * Tuning.horrorProgramPauseFraction {
            let tau = rms > programRMS ? Tuning.horrorProgramRiseSeconds : Tuning.horrorProgramFallSeconds
            programRMS = max(Tuning.horrorProgramFloor, programRMS + (rms - programRMS) * min(1, dt / tau))
        }

        // Ce qui menace : le niveau au-dessus des dialogues, les basses et les aigus TENUS.
        horrorLevel += (rms - horrorLevel) * min(1, dt * Tuning.horrorLevelSmoothingRate)
        let tension = Self.ramp(horrorLevel / programRMS,
                                from: Tuning.horrorTensionKneeLow, to: Tuning.horrorTensionKneeHigh)
        let pureBass = max(0, frame.bass - Tuning.horrorVoiceMidFactor * frame.mid)
        let rumble = Self.ramp(sustainedBass.push(pureBass, at: time),
                               from: Tuning.horrorRumbleGateLow, to: Tuning.horrorRumbleGateHigh)
        let stridence = Self.ramp(sustainedHigh.push(frame.high, at: time),
                                  from: Tuning.horrorStridenceGateLow, to: Tuning.horrorStridenceGateHigh)

        rotationClock += dt
        if rotationClock >= Tuning.horrorRotationSeconds {
            rotationClock = 0
            rotation += 1
        }

        // Le réglage « Flash » dose l'éclair (0 = aucun flash, défaut = éclair plein).
        let lightning = flash * min(1, tuning.flash / Tuning.horrorFlashReference)
        flash = max(0, flash - dt * Tuning.horrorFlashDecayPerSecond)

        let hues = anchors.flatMap { $0.isEmpty ? nil : $0 } ?? Tuning.horrorDefaultAnchors
        let saturation = Tuning.horrorSaturation * (1 - Tuning.horrorFlashDesaturation * lightning)
        let ordered = Self.orderedIndices(channels)

        return channels.indices.map { index in
            let slot = ordered[index]
            // Une lampe sur deux ajoute la stridence (et gronde un peu moins) : la pièce ne
            // réagit pas d'un bloc.
            let strident = slot % 2 == 1
            let menace = tension * Tuning.horrorTensionGain
                + rumble * Tuning.horrorRumbleGain * (strident ? Tuning.horrorRumbleOnStridentLamps : 1)
                + (strident ? stridence * Tuning.horrorStridenceGain : 0)
            let glow = Tuning.horrorBaseBrightness + menace * tuning.sensitivity
            // Vacillement d'inquiétude : deux sinus incommensurables, déphasés par lampe
            // (déterministe — le mapper reste rejouable à l'identique).
            let unease = 0.5 + 0.5 * sin(time * 2.3 + Double(slot) * 1.7) * sin(time * 5.9 + Double(slot) * 0.6)
            let flicker = 1 - Tuning.horrorFlickerDepth * unease
            let brightness = min(1, min(1, glow) * flicker + lightning)
            return color(channel: channels[index].id, hue: hues[(slot + rotation) % hues.count],
                         saturation: saturation, value: brightness)
        }
    }

    /// Rampe linéaire bornée : 0 sous `from`, 1 au-dessus de `to`.
    private static func ramp(_ value: Double, from low: Double, to high: Double) -> Double {
        min(1, max(0, (value - low) / (high - low)))
    }

    // MARK: - Palette, tempo, teinte

    /// Teintes disponibles pour les lampes : les ancres du thème, ou — en spectre libre —
    /// des teintes étalées autour de la teinte de base (une par lampe).
    private func paletteHues(count: Int, spread: Double) -> [Double] {
        if let anchors, !anchors.isEmpty { return anchors }
        let n = max(1, count)
        return (0..<n).map { baseHue + spread * (Double($0) - Double(n - 1) / 2) }
    }

    /// Rang de chaque channel de gauche à droite : rôles et palette suivent la
    /// géométrie de la pièce, pas l'ordre arbitraire des ids.
    private static func orderedIndices(_ channels: [SyncChannel]) -> [Int] {
        let sorted = channels.indices.sorted { channels[$0].x < channels[$1].x }
        var rank = [Int](repeating: 0, count: channels.count)
        for (position, index) in sorted.enumerated() { rank[index] = position }
        return rank
    }

    /// Beat détecté : la palette tourne d'une lampe, le compteur de mesure avance,
    /// le flash est plus fort sur le temps fort, et le tempo se réestime.
    private mutating func registerBeat(at time: Double) {
        if let last = lastBeatTime {
            let interval = time - last
            if interval > Tuning.maxBeatInterval * 2 {
                beatIndex = 0 // silence ou break : on repart en début de mesure
                beatIntervals.removeAll()
            } else {
                beatIndex = (beatIndex + 1) % 4
                if (Tuning.minBeatInterval...Tuning.maxBeatInterval).contains(interval) {
                    beatIntervals.append(interval)
                    if beatIntervals.count > Tuning.tempoHistory { beatIntervals.removeFirst() }
                }
            }
        }
        lastBeatTime = time
        if mode == .club { rotation += 1 }
        flash = beatIndex == 0 ? Tuning.downbeatBoost : 1.0
        estimatedBPM = beatIntervals.count >= 4 ? 60 / beatIntervals.sorted()[beatIntervals.count / 2] : nil
    }

    /// Tire la teinte de fond vers celle correspondant à la chaleur du son
    /// (distance circulaire — le chemin passe par les violets, l'axe thermique).
    private mutating func pullHueTowardWarmth(dt: Double, rate: Double) {
        let target = Tuning.coldHue + smoothedWarmth * Tuning.warmHueSpan
        var delta = (target - baseHue).truncatingRemainder(dividingBy: 1)
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        baseHue = (baseHue + delta * min(1, dt * rate) + 1).truncatingRemainder(dividingBy: 1)
    }

    // MARK: - Sortie

    /// EMA asymétrique par composante : l'attaque garde le punch des beats,
    /// la descente évite les flips secs de couleur.
    private mutating func smoothedColor(_ target: ChannelColor, dt: Double) -> ChannelColor {
        var (tauUp, tauDown) = switch mode {
        case .club: (Tuning.clubAttack, Tuning.clubRelease)
        case .chill: (Tuning.chillAttack, Tuning.chillRelease)
        case .horror: (Tuning.horrorAttack, Tuning.horrorRelease)
        }
        tauUp /= max(0.1, tuning.punch) // punch élevé = attaque plus sèche
        guard let previous = smoothedOutput[target.channel] else {
            smoothedOutput[target.channel] = (target.red, target.green, target.blue)
            return target
        }
        func step(_ prev: Double, _ next: Double) -> Double {
            prev + (next - prev) * min(1, dt / (next > prev ? tauUp : tauDown))
        }
        let value = (red: step(previous.red, target.red),
                     green: step(previous.green, target.green),
                     blue: step(previous.blue, target.blue))
        smoothedOutput[target.channel] = value
        return ChannelColor(channel: target.channel, red: value.red, green: value.green, blue: value.blue)
    }

    /// HSV -> RGB (h, s, v dans 0...1), avec master de luminosité puis levée perceptuelle sur v.
    private func color(channel: UInt8, hue: Double, saturation: Double, value rawValue: Double) -> ChannelColor {
        let value = pow(min(1, max(0, rawValue) * tuning.brightness), Tuning.brightnessGamma)
        let h = (hue - floor(hue)) * 6
        let sector = Int(h) % 6
        let f = h - floor(h)
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * f)
        let t = value * (1 - saturation * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch sector {
        case 0: (value, t, p)
        case 1: (q, value, p)
        case 2: (p, value, t)
        case 3: (p, q, value)
        case 4: (t, p, value)
        default: (value, p, q)
        }
        return ChannelColor(channel: channel, red: r, green: g, blue: b)
    }
}
