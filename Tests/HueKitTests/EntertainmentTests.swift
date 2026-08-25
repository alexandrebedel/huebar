import Foundation
import Testing
@testable import HueKit

// MARK: - B1 : clientKey dans HueConfig

@Test func parsesClientKey() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).env")
    try "export HUE_BRIDGE=1.2.3.4\nexport HUE_KEY=abc\nexport HUE_CLIENTKEY=05C37B87131DA78EA028CE0429AE3F94\n"
        .write(to: file, atomically: true, encoding: .utf8)
    let config = try HueConfig.load(path: file.path)
    #expect(config.clientKey == "05C37B87131DA78EA028CE0429AE3F94")
    #expect(config.clientKeyBytes == Data([0x05, 0xC3, 0x7B, 0x87, 0x13, 0x1D, 0xA7, 0x8E,
                                           0xA0, 0x28, 0xCE, 0x04, 0x29, 0xAE, 0x3F, 0x94]))
}

@Test func missingClientKeyIsNil() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).env")
    try "export HUE_BRIDGE=1.2.3.4\nexport HUE_KEY=abc\n".write(to: file, atomically: true, encoding: .utf8)
    let config = try HueConfig.load(path: file.path)
    #expect(config.clientKey == nil)
    #expect(config.clientKeyBytes == nil)
}

// MARK: - B2 : encodage HueStream v2

private let configID = "bce767fc-ddba-4747-bec1-2313f5dfbbac" // 36 chars

@Test func encodesFrameHeader() {
    let data = HueStreamEncoder.frame(configID: configID, sequence: 7, channels: [])
    #expect(data.count == 52)
    #expect(Array(data.prefix(9)) == Array("HueStream".utf8))
    #expect(data[9] == 0x02)   // version major
    #expect(data[10] == 0x00)  // version minor
    #expect(data[11] == 7)     // sequence
    #expect(data[12] == 0x00 && data[13] == 0x00)
    #expect(data[14] == 0x00)  // color space RGB
    #expect(data[15] == 0x00)
    #expect(Array(data[16..<52]) == Array(configID.utf8))
}

@Test func encodesChannelsBigEndianSortedById() {
    let channels = [
        ChannelColor(channel: 2, red: 0, green: 0.5, blue: 1),
        ChannelColor(channel: 0, red: 1, green: 0, blue: 0),
    ]
    let data = HueStreamEncoder.frame(configID: configID, sequence: 0, channels: channels)
    #expect(data.count == 52 + 14)
    let ch0 = Array(data[52..<59])
    #expect(ch0 == [0, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00])          // rouge plein
    let ch2 = Array(data[59..<66])
    #expect(ch2[0] == 2)
    #expect(ch2[1] == 0x00 && ch2[2] == 0x00)                        // R = 0
    #expect(ch2[3] == 0x80 && ch2[4] == 0x00)                        // G = 0.5 -> round(32767.5) = 32768 BE
    #expect(ch2[5] == 0xFF && ch2[6] == 0xFF)                        // B = 1
}

@Test func clampsOutOfRangeValues() {
    let data = HueStreamEncoder.frame(configID: configID, sequence: 0,
                                      channels: [ChannelColor(channel: 0, red: -1, green: 2, blue: 0.0)])
    let ch = Array(data[52..<59])
    #expect(ch[1] == 0x00 && ch[2] == 0x00)   // clamped à 0
    #expect(ch[3] == 0xFF && ch[4] == 0xFF)   // clamped à 1
}
