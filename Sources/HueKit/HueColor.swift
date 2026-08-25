import Foundation

public enum HueColor {
    /// RGB (0...1) -> point xy CIE 1931, formule Philips Hue.
    public static func xy(red: Double, green: Double, blue: Double) -> XY {
        func gamma(_ c: Double) -> Double {
            c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92
        }
        let r = gamma(red), g = gamma(green), b = gamma(blue)
        let X = r * 0.664511 + g * 0.154324 + b * 0.162028
        let Y = r * 0.283881 + g * 0.668433 + b * 0.047685
        let Z = r * 0.000088 + g * 0.072310 + b * 0.986039
        let sum = X + Y + Z
        guard sum > 0 else { return XY(x: 0.3127, y: 0.3290) } // blanc D65
        return XY(x: X / sum, y: Y / sum)
    }

    /// Point xy CIE -> RGB (0...1) pour l'affichage (pastilles couleur).
    public static func rgb(from xy: XY, brightness: Double = 1) -> (red: Double, green: Double, blue: Double) {
        guard xy.y > 0 else { return (0, 0, 0) }
        let Y = brightness
        let X = (Y / xy.y) * xy.x
        let Z = (Y / xy.y) * (1 - xy.x - xy.y)

        var r = X * 1.656492 - Y * 0.354851 - Z * 0.255038
        var g = -X * 0.707196 + Y * 1.655397 + Z * 0.036152
        var b = X * 0.051713 - Y * 0.121364 + Z * 1.011530

        let maxComponent = max(r, g, b)
        if maxComponent > 1 { r /= maxComponent; g /= maxComponent; b /= maxComponent }

        func reverseGamma(_ c: Double) -> Double {
            let clamped = max(0, c)
            return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return (min(1, reverseGamma(r)), min(1, reverseGamma(g)), min(1, reverseGamma(b)))
    }

    /// Température mirek (1e6/K) -> RGB (0...1) pour l'affichage.
    /// Approximation blackbody de Tanner Helland, suffisante pour des aperçus.
    public static func rgb(fromMirek mirek: Int) -> (red: Double, green: Double, blue: Double) {
        let kelvin = 1_000_000.0 / Double(max(mirek, 1))
        let t = min(max(kelvin, 1000), 40000) / 100
        func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }

        let red = t <= 66 ? 1 : clamp01(329.698727446 * pow(t - 60, -0.1332047592) / 255)
        let green = t <= 66
            ? clamp01((99.4708025861 * log(t) - 161.1195681661) / 255)
            : clamp01(288.1221695283 * pow(t - 60, -0.0755148492) / 255)
        let blue: Double
        if t >= 66 {
            blue = 1
        } else if t <= 19 {
            blue = 0
        } else {
            blue = clamp01((138.5177312231 * log(t - 10) - 305.0447927307) / 255)
        }
        return (red, green, blue)
    }
}
