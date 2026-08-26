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

/// Transforme les frames d'analyse en couleurs par channel. À état (déterministe pour un
/// même enchaînement d'appels) : teinte tournante, decay de flash, lissages.
public struct LightMapper {
    /// Toutes les constantes de rendu — le « feel » de la sync se règle ici.
    enum Tuning {
        /// Sous ~0.5 en linéaire les Hue paraissent éteintes : levée perceptuelle.
        static let brightnessGamma = 0.6

        // Lissage des entrées d'analyse.
        static let rmsInputGain = 3.2
        static let rmsSmoothingRate = 4.5  // 1/s — suit le morceau de près (Chill réactif)
        static let bassSmoothingRate = 5.0 // 1/s

        // Lissage de sortie par channel (EMA asymétrique), en secondes.
        static let clubAttack = 0.12, clubRelease = 0.30
        static let chillAttack = 0.08, chillRelease = 0.35

        // Club.
        static let clubHueDriftPerSecond = 0.02
        static let clubBeatHueJump = 0.05
        static let clubFlashDecayPerSecond = 4.0 // extinction du flash ~250 ms
        static let clubBassWeight = 0.6, clubMidWeight = 0.3, clubHighWeight = 0.2
        static let clubBaseBrightness = 0.10
        static let clubEnergyGain = 0.85
        static let clubMinSaturation = 0.55
        static let clubHighDesaturation = 0.5
        static let clubChannelHueSpread = 0.06
        static let clubHighHueShift = 0.05

        // Chaleur du son (centroïde spectral) → teinte cible, le long de l'axe
        // « thermique » bleu → violet → rouge/orange (jamais par le vert).
        static let coldHue = 0.58            // bleu (son brillant)
        static let warmHueSpan = 0.45        // 0.58 + 0.45 ≈ 0.03 : orange (son sombre)
        static let warmthSmoothingRate = 2.0 // 1/s
        static let chillWarmthPullPerSecond = 0.25
        static let clubWarmthPullPerSecond = 0.08 // léger : la rotation de teinte garde la main

        // Chill.
        static let chillHueDriftPerSecond = 0.015
        static let chillBaseBrightness = 0.12
        static let chillRMSGain = 1.05
        static let chillBassGain = 0.45
        static let chillMidGain = 0.12
        static let chillSaturation = 0.6
        static let chillChannelHueSpread = 0.04

        /// Fraction de teinte libre conservée autour de l'ancre d'un thème.
        static let themeLooseness = 0.15
    }

    private let mode: SyncMode
    /// Ancres de teinte imposées (nil = spectre libre), modifiables en cours de route.
    public var anchors: [Double]?
    /// Réglages utilisateur, modifiables en cours de route sans reset de l'état.
    public var tuning: SyncTuning
    private var baseHue = 0.62 // départ bleu nuit
    private var flash = 0.0    // niveau de flash (Club), décroît vite
    private var smoothedRMS = 0.0
    private var smoothedBass = 0.0
    private var smoothedWarmth = 0.5
    private var lastTime: Double?
    private var smoothedOutput: [UInt8: (red: Double, green: Double, blue: Double)] = [:]

    public init(mode: SyncMode, anchors: [Double]? = nil, tuning: SyncTuning = .default) {
        self.mode = mode
        self.anchors = anchors
        self.tuning = tuning
    }

    public mutating func map(frame: AnalysisFrame, channels: [SyncChannel], time: Double) -> [ChannelColor] {
        let dt = lastTime.map { max(0, min(0.2, time - $0)) } ?? 0.02
        lastTime = time
        smoothedRMS += (min(1, frame.rms * Tuning.rmsInputGain) - smoothedRMS)
            * min(1, dt * Tuning.rmsSmoothingRate)
        smoothedBass += (frame.bass - smoothedBass) * min(1, dt * Tuning.bassSmoothingRate)
        smoothedWarmth += (frame.warmth - smoothedWarmth) * min(1, dt * Tuning.warmthSmoothingRate)

        let targets = switch mode {
        case .club: mapClub(frame: frame, channels: channels, dt: dt)
        case .chill: mapChill(frame: frame, channels: channels, dt: dt)
        }
        // Lissage de sortie : les sauts de teinte/flash deviennent des transitions,
        // sans tuer l'attaque (montée plus rapide que la descente).
        return targets.map { smoothedColor($0, dt: dt) }
    }

    private mutating func mapClub(frame: AnalysisFrame, channels: [SyncChannel], dt: Double) -> [ChannelColor] {
        baseHue = (baseHue + dt * Tuning.clubHueDriftPerSecond).truncatingRemainder(dividingBy: 1)
        if frame.beat {
            baseHue = (baseHue + Tuning.clubBeatHueJump).truncatingRemainder(dividingBy: 1)
            flash = 1.0
        }
        pullHueTowardWarmth(dt: dt, rate: Tuning.clubWarmthPullPerSecond)
        flash = max(0, flash - dt * Tuning.clubFlashDecayPerSecond)

        // Mix spectral : les basses portent, mais nappes (mids) et hats (aigus) participent.
        let energy = min(1, (smoothedBass * Tuning.clubBassWeight
            + frame.mid * Tuning.clubMidWeight
            + frame.high * Tuning.clubHighWeight) * tuning.sensitivity)
        let brightness = min(1, Tuning.clubBaseBrightness + energy * Tuning.clubEnergyGain
            + flash * tuning.flash)
        let saturation = max(Tuning.clubMinSaturation,
                             1 - min(0.4, frame.high * Tuning.clubHighDesaturation))
        let anchoredHue = themedHue(baseHue + frame.high * Tuning.clubHighHueShift)

        return channels.map { channel in
            // Décalage de teinte par position pour un rendu spatial.
            let hue = anchoredHue + channel.x * Tuning.clubChannelHueSpread
            return color(channel: channel.id, hue: hue, saturation: saturation, value: brightness)
        }
    }

    private mutating func mapChill(frame: AnalysisFrame, channels: [SyncChannel], dt: Double) -> [ChannelColor] {
        // Dérive lente pour la vie ; la chaleur du son pilote la teinte de fond.
        baseHue = (baseHue + dt * Tuning.chillHueDriftPerSecond).truncatingRemainder(dividingBy: 1)
        pullHueTowardWarmth(dt: dt, rate: Tuning.chillWarmthPullPerSecond)

        // Respire avec le morceau : RMS large bande + houle des basses.
        let brightness = min(1, Tuning.chillBaseBrightness + (smoothedRMS * Tuning.chillRMSGain
            + smoothedBass * Tuning.chillBassGain + frame.mid * Tuning.chillMidGain) * tuning.sensitivity)
        let anchoredHue = themedHue(baseHue)

        return channels.map { channel in
            let hue = anchoredHue + channel.x * Tuning.chillChannelHueSpread
            return color(channel: channel.id, hue: hue, saturation: Tuning.chillSaturation, value: brightness)
        }
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

    /// Attire la teinte vers l'ancre du thème la plus proche (distance circulaire),
    /// en gardant une fraction de teinte libre pour les micro-variations.
    private func themedHue(_ hue: Double) -> Double {
        guard let anchors, !anchors.isEmpty else { return hue }
        let h = hue - floor(hue)
        var best = anchors[0]
        var bestDistance = 1.0
        for anchor in anchors {
            let direct = abs(h - anchor)
            let distance = min(direct, 1 - direct)
            if distance < bestDistance {
                bestDistance = distance
                best = anchor
            }
        }
        var delta = h - best
        if delta > 0.5 { delta -= 1 }
        if delta < -0.5 { delta += 1 }
        return best + delta * Tuning.themeLooseness
    }

    /// EMA asymétrique par composante : l'attaque garde le punch des beats,
    /// la descente évite les flips secs de couleur.
    private mutating func smoothedColor(_ target: ChannelColor, dt: Double) -> ChannelColor {
        var (tauUp, tauDown) = mode == .club
            ? (Tuning.clubAttack, Tuning.clubRelease)
            : (Tuning.chillAttack, Tuning.chillRelease)
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

    /// HSV -> RGB (h, s, v dans 0...1), avec levée perceptuelle sur v.
    private func color(channel: UInt8, hue: Double, saturation: Double, value rawValue: Double) -> ChannelColor {
        let value = pow(max(0, rawValue), Tuning.brightnessGamma)
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
