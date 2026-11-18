import AppIntents
import SwiftUI
import WidgetKit

@main
struct ShootDayWidgets: WidgetBundle {
    var body: some Widget {
        ShootDayControl()
    }
}

/// The lock-screen / Control Centre button (iOS 18): one press opens the pinned PDF.
/// Swap it in for the torch: hold the lock screen › Customise › Lock Screen › tap a button.
struct ShootDayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.outandscout.app.shootday") {
            ControlWidgetButton(action: OpenShootDayIntent()) {
                Label("Shoot day", systemImage: "doc.text")
            }
        }
        .displayName("Shoot day")
        .description("Opens the shot list or call sheet you pinned in Out & Scout.")
    }
}
