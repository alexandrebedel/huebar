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
    private let mode: SyncMode
    private var baseHue = 0.62      // départ bleu nuit
    private var flash = 0.0         // niveau de flash (Club), décroît vite
    private var smoothedRMS = 0.0
    private var smoothedBass = 0.0
    private var lastTime: Double?
    private var smoothedOutput: [UInt8: (red: Double, green: Double, blue: Double)] = [:]

    public init(mode: SyncMode) {
        self.mode = mode
    }

    public mutating func map(frame: AnalysisFrame, channels: [SyncChannel], time: Double) -> [ChannelColor] {
        let dt = lastTime.map { max(0, min(0.2, time - $0)) } ?? 0.02
        lastTime = time
        smoothedRMS += (min(1, frame.rms * 2.5) - smoothedRMS) * min(1, dt * 3)
        smoothedBass += (frame.bass - smoothedBass) * min(1, dt * 5)

        let targets = switch mode {
        case .club: mapClub(frame: frame, channels: channels, dt: dt)
        case .chill: mapChill(frame: frame, channels: channels, dt: dt)
        }
        // Lissage de sortie par channel : les sauts de teinte/flash deviennent des
        // transitions, sans tuer l'attaque (montée plus rapide que la descente).
        return targets.map { smoothedColor($0, dt: dt) }
    }

    private mutating func mapClub(frame: AnalysisFrame, channels: [SyncChannel], dt: Double) -> [ChannelColor] {
        baseHue = (baseHue + dt * 0.02).truncatingRemainder(dividingBy: 1)
        if frame.beat {
            baseHue = (baseHue + 0.13).truncatingRemainder(dividingBy: 1)
            flash = 1.0
        }
        flash = max(0, flash - dt * 6) // decay ~170 ms

        // Mix spectral : les basses portent, mais mids/aigus (nappes, hats) participent
        // aussi à la luminosité — retour utilisateur : « très axé sur les basses ».
        let energy = min(1, smoothedBass * 0.7 + frame.mid * 0.35 + frame.high * 0.25)
        let brightness = min(1, 0.06 + energy * 0.85 + flash * 0.6)
        let saturation = max(0.55, 1 - min(0.4, frame.high * 0.5))

        return channels.map { channel in
            // Décalage de teinte par position pour un rendu spatial, aigus vers la droite.
            let hue = (baseHue + channel.x * 0.06 + frame.high * 0.05 + 1).truncatingRemainder(dividingBy: 1)
            return color(channel: channel.id, hue: hue, saturation: saturation, value: brightness)
        }
    }

    private mutating func mapChill(frame: AnalysisFrame, channels: [SyncChannel], dt: Double) -> [ChannelColor] {
        // Dérive lente ; le spectre tire doucement la teinte (aigus -> plus chaud).
        let spectralPull = min(0.3, frame.high * 0.4) - min(0.2, frame.bass * 0.2)
        baseHue = (baseHue + dt * (0.008 + spectralPull * 0.02) + 1).truncatingRemainder(dividingBy: 1)

        let brightness = min(1, 0.10 + smoothedRMS * 1.2 + frame.mid * 0.15)
        let saturation = 0.6

        return channels.map { channel in
            let hue = (baseHue + channel.x * 0.04 + 1).truncatingRemainder(dividingBy: 1)
            return color(channel: channel.id, hue: hue, saturation: saturation, value: brightness)
        }
    }

    /// EMA asymétrique par composante : l'attaque (τ court) garde le punch des beats,
    /// la descente (τ long) évite les flips secs de couleur.
    private mutating func smoothedColor(_ target: ChannelColor, dt: Double) -> ChannelColor {
        let (tauUp, tauDown) = mode == .club ? (0.05, 0.22) : (0.30, 0.45)
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

    /// HSV -> RGB (h, s, v dans 0...1).
    private func color(channel: UInt8, hue: Double, saturation: Double, value rawValue: Double) -> ChannelColor {
        // Levée perceptuelle : sous ~0.5 en linéaire les Hue paraissent presque éteintes
        // (retour utilisateur : « ça éclaire rien ») ; gamma 0.6 remonte les niveaux moyens
        // sans écraser la dynamique ni allumer le silence.
        let value = pow(max(0, rawValue), 0.6)
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
