import Foundation
import Testing
@testable import HueKit

@Test func parsesEnvFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("credentials.env")
    try "# commentaire\nexport HUE_BRIDGE=192.168.1.134\nHUE_KEY=\"abc123\"\n"
        .write(to: file, atomically: true, encoding: .utf8)

    let config = try HueConfig.load(path: file.path)
    #expect(config.bridgeIP == "192.168.1.134")
    #expect(config.appKey == "abc123")
}

@Test func throwsWhenFileMissing() {
    #expect(throws: HueError.self) {
        try HueConfig.load(path: "/nonexistent/credentials.env")
    }
}

@Test func throwsWhenKeyMissing() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).env")
    try "export HUE_BRIDGE=192.168.1.134\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(throws: HueError.self) {
        try HueConfig.load(path: file.path)
    }
}
