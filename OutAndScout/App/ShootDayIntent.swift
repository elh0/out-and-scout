import AppIntents
import Foundation

/// Opens the PDF pinned for the shoot day. Compiled into both the app and the widget
/// extension: because it opens the app, iOS runs `perform()` in the app's own process,
/// which then shows the PDF full screen (after Face ID, which iOS always asks for).
struct OpenShootDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open shoot day PDF"
    static let description = IntentDescription("Opens the shot list or call sheet you pinned for the shoot day.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShootDayLink.request()
        return .result()
    }
}

/// How the lock-screen button tells the app to open the pinned PDF. A flag (for a cold
/// launch, read once the app is up) plus a notification (when it's already running).
enum ShootDayLink {
    static let flagKey = "shootDayOpenRequested"
    static let notification = Notification.Name("OutAndScoutOpenShootDay")

    @MainActor
    static func request() {
        UserDefaults.standard.set(true, forKey: flagKey)
        NotificationCenter.default.post(name: notification, object: nil)
    }

    /// True once if the button asked for the PDF; clears the flag.
    static func takeRequest() -> Bool {
        let asked = UserDefaults.standard.bool(forKey: flagKey)
        if asked { UserDefaults.standard.set(false, forKey: flagKey) }
        return asked
    }
}
