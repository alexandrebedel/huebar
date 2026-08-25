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
