import AppIntents
import SwiftUI
import WidgetKit

@main
struct HueBarControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alexbedel.huebar.panel") {
            ControlWidgetButton(action: OpenPanelIntent()) {
                Label("HueBar", systemImage: "lightbulb.fill")
            }
        }
        .displayName("HueBar")
        .description("Ouvre le panneau HueBar.")
    }
}

struct OpenPanelIntent: AppIntent {
    static let title: LocalizedStringResource = "Ouvrir le panneau HueBar"
    static let isDiscoverable: Bool = false
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "huebar://panel")!))
    }
}
