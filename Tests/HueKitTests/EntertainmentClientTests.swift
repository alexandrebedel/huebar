import Foundation
import Testing
@testable import HueKit

// Extension de HueClientTests : même suite .serialized, car MockURLProtocol.handler
// est un static partagé — deux suites distinctes tourneraient en parallèle et se croiseraient.
extension HueClientTests {
    @Test func fetchesEntertainmentConfigurations() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString
                == "https://192.168.1.134/clip/v2/resource/entertainment_configuration")
            return self.ok(request, """
            {"errors":[],"data":[{"id":"bce767fc-ddba-4747-bec1-2313f5dfbbac","type":"entertainment_configuration",
              "metadata":{"name":"HueBar Sync"},"configuration_type":"music","status":"inactive",
              "channels":[
                {"channel_id":0,"position":{"x":-1.0,"y":1.0,"z":0.0},"members":[{"service":{"rid":"E1","rtype":"entertainment"},"index":0}]},
                {"channel_id":1,"position":{"x":0.5,"y":1.0,"z":0.0},"members":[{"service":{"rid":"E2","rtype":"entertainment"},"index":0}]}
              ]}]}
            """)
        }
        let configs = try await makeClient().fetchEntertainmentConfigurations()
        #expect(configs.count == 1)
        #expect(configs[0].metadata.name == "HueBar Sync")
        #expect(configs[0].status == "inactive")
        #expect(configs[0].channels.map(\.channelID) == [0, 1])
        #expect(configs[0].channels[0].position.x == -1.0)
    }

    @Test func startAndStopPutAction() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString
                == "https://192.168.1.134/clip/v2/resource/entertainment_configuration/Z1")
            #expect(request.httpMethod == "PUT")
            let body = String(data: request.bodyData ?? Data(), encoding: .utf8)
            #expect(body == #"{"action":"start"}"#)
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().startEntertainment(id: "Z1")

        MockURLProtocol.handler = { request in
            let body = String(data: request.bodyData ?? Data(), encoding: .utf8)
            #expect(body == #"{"action":"stop"}"#)
            return self.ok(request, #"{"errors":[],"data":[]}"#)
        }
        try await makeClient().stopEntertainment(id: "Z1")
    }

    @Test func fetchesApplicationIDFromAuthHeader() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://192.168.1.134/auth/v1")
            #expect(request.value(forHTTPHeaderField: "hue-application-key") == "test-key")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["hue-application-id": "abcd1234-ab12-ab12-ab12-abcdef123456"])!
            return (response, Data())
        }
        let appID = try await makeClient().fetchApplicationID()
        #expect(appID == "abcd1234-ab12-ab12-ab12-abcdef123456")
    }
}
