import Foundation
import Testing
@testable import HueKit

@Suite(.serialized)
struct HueClientTests {
    func makeClient() -> HueClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return HueClient(
            config: HueConfig(bridgeIP: "192.168.1.134", appKey: "test-key"),
            sessionConfiguration: configuration
        )
    }

    func ok(_ request: URLRequest, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
         Data(body.utf8))
    }

    @Test func fetchLightsSendsKeyAndDecodes() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/clip/v2/resource/light")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "hue-application-key") == "test-key")
            return self.ok(request, """
            {"errors":[],"data":[{"id":"L1","metadata":{"name":"Go"},"on":{"on":true},
             "owner":{"rid":"D1","rtype":"device"}}]}
            """)
        }
        let lights = try await makeClient().fetchLights()
        #expect(lights.map(\.id) == ["L1"])
    }

    @Test func updateLightPutsEncodedBody() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/clip/v2/resource/light/L1")
            #expect(request.httpMethod == "PUT")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = String(data: request.bodyData ?? Data(), encoding: .utf8)
            #expect(body == #"{"on":{"on":false}}"#)
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().updateLight(id: "L1", LightUpdate(on: OnState(on: false)))
    }

    @Test func recallScenePutsRecallBody() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/clip/v2/resource/scene/S1")
            let body = String(data: request.bodyData ?? Data(), encoding: .utf8)
            #expect(body == #"{"recall":{"action":"active"}}"#)
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().recallScene(id: "S1")
    }

    @Test func renameLightPutsMetadataName() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/clip/v2/resource/light/L1")
            #expect(request.httpMethod == "PUT")
            let body = String(data: request.bodyData ?? Data(), encoding: .utf8)
            #expect(body == #"{"metadata":{"name":"Bureau"}}"#)
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().renameLight(id: "L1", name: "Bureau")
    }

    @Test func renameRoomAndSceneTargetTheirResource() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/clip/v2/resource/room/R1")
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().renameRoom(id: "R1", name: "Salon")

        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/clip/v2/resource/scene/S1")
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().renameScene(id: "S1", name: "Soirée")
    }

    @Test func non200ThrowsBadStatus() async {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
             Data())
        }
        await #expect(throws: HueError.badStatus(503)) {
            try await self.makeClient().fetchRooms()
        }
    }
}
