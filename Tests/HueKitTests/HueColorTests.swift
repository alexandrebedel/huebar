import Testing
@testable import HueKit

private func near(_ a: Double, _ b: Double, tolerance: Double = 0.01) -> Bool {
    abs(a - b) <= tolerance
}

@Test func redToXY() {
    let xy = HueColor.xy(red: 1, green: 0, blue: 0)
    #expect(near(xy.x, 0.7006))
    #expect(near(xy.y, 0.2993))
}

@Test func whiteToXY() {
    let xy = HueColor.xy(red: 1, green: 1, blue: 1)
    #expect(near(xy.x, 0.3227))
    #expect(near(xy.y, 0.3290))
}

@Test func blackFallsBackToWhitePoint() {
    let xy = HueColor.xy(red: 0, green: 0, blue: 0)
    #expect(near(xy.x, 0.3127))
    #expect(near(xy.y, 0.3290))
}

@Test func redRoundTrip() {
    let rgb = HueColor.rgb(from: XY(x: 0.7006, y: 0.2993))
    #expect(rgb.red > 0.9)
    #expect(rgb.green < 0.1)
    #expect(rgb.blue < 0.1)
}

@Test func zeroYProducesBlack() {
    let rgb = HueColor.rgb(from: XY(x: 0.3, y: 0))
    #expect(rgb.red == 0 && rgb.green == 0 && rgb.blue == 0)
}
