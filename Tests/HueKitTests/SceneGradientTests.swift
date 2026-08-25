import Foundation
import Testing
@testable import HueKit

struct SceneGradientTests {
    private func scene(actions: [SceneAction]?) -> HueScene {
        HueScene(
            id: "S1", metadata: Metadata(name: "Test"),
            group: ResourceRef(rid: "R1", rtype: "room"), actions: actions
        )
    }

    private func colorAction(x: Double, y: Double, on: Bool = true) -> SceneAction {
        SceneAction(action: .init(on: OnState(on: on), color: ColorState(xy: XY(x: x, y: y))))
    }

    private func mirekAction(_ mirek: Int, on: Bool = true) -> SceneAction {
        SceneAction(action: .init(on: OnState(on: on), colorTemperature: ColorTemperatureState(mirek: mirek)))
    }

    @Test func colorSceneKeepsBridgeOrder() {
        let stops = SceneGradient.stops(for: scene(actions: [
            colorAction(x: 0.675, y: 0.322), // rouge
            colorAction(x: 0.167, y: 0.040), // bleu
        ]))
        #expect(stops.count == 2)
        #expect(stops[0].red > stops[0].blue)
        #expect(stops[1].blue > stops[1].red)
    }

    @Test func mirekWarmIsRedderThanCold() {
        let warm = SceneGradient.stops(for: scene(actions: [mirekAction(454)]))[0]
        let cold = SceneGradient.stops(for: scene(actions: [mirekAction(153)]))[0]
        #expect(warm.red > warm.blue)
        #expect(warm.blue < cold.blue)
    }

    @Test func consecutiveDuplicatesAreMerged() {
        let stops = SceneGradient.stops(for: scene(actions: [
            mirekAction(200), mirekAction(200), mirekAction(200),
        ]))
        #expect(stops.count == 1)
    }

    @Test func offLightsAreIgnored() {
        let stops = SceneGradient.stops(for: scene(actions: [
            colorAction(x: 0.675, y: 0.322, on: false),
            mirekAction(454),
        ]))
        #expect(stops.count == 1)
        #expect(stops[0].red > stops[0].blue) // seul le mirek chaud reste
    }

    @Test func emptySceneFallsBackToWarmWhite() {
        for actions in [nil, [], [SceneAction(action: .init(on: OnState(on: true)))]] as [[SceneAction]?] {
            let stops = SceneGradient.stops(for: scene(actions: actions))
            #expect(stops.count == 1)
            #expect(stops[0].red == 1.0)
            #expect(stops[0].red > stops[0].blue)
        }
    }

    @Test func stopsAreCappedAtFive() {
        let actions = (1...8).map { colorAction(x: 0.1 + Double($0) * 0.06, y: 0.3) }
        #expect(SceneGradient.stops(for: scene(actions: actions)).count == 5)
    }

    @Test func sceneActionsDecodeFromClipJSON() throws {
        let json = """
        {"id":"S1","metadata":{"name":"Stimulation"},"group":{"rid":"R1","rtype":"room"},
         "actions":[
           {"target":{"rid":"L1","rtype":"light"},
            "action":{"on":{"on":true},"dimming":{"brightness":100.0},
                      "color_temperature":{"mirek":156}}},
           {"target":{"rid":"L2","rtype":"light"},
            "action":{"on":{"on":true},"color":{"xy":{"x":0.675,"y":0.322}}}}
         ]}
        """
        let decoded = try JSONDecoder().decode(HueScene.self, from: Data(json.utf8))
        #expect(decoded.actions?.count == 2)
        #expect(decoded.actions?[0].action.colorTemperature?.mirek == 156)
        #expect(decoded.actions?[1].action.color?.xy == XY(x: 0.675, y: 0.322))
        #expect(SceneGradient.stops(for: decoded).count == 2)
    }
}
