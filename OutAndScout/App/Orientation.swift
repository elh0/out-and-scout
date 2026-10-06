import SwiftUI
import UIKit

/// Portrait or landscape is picked with the switch, not by tilting the phone. Landscape
/// still flips between its two sides; it never drops into portrait on its own.
@Observable final class LayoutMode {
    static let shared = LayoutMode()
    private static let key = "upright"

    /// The portrait layouts are showing. The app always opens in landscape, as Elliot
    /// asked; portrait is a switch away.
    private(set) var portrait = false
    /// True for the moment the screen is turning; the controls fade back in after.
    private(set) var turning = false

    /// What the app allows right now; read by the app delegate.
    var mask: UIInterfaceOrientationMask { portrait ? .portrait : .landscape }

    /// Switches the layout and turns the screen to match.
    func set(portrait: Bool, remember: Bool = true) {
        if remember { UserDefaults.standard.set(portrait, forKey: Self.key) }
        guard portrait != self.portrait else { return }
        // Hide the controls straight away (no animation), turn the screen, then fade them in
        // once the new layout is in place.
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            turning = true
            self.portrait = portrait
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeOut(duration: 0.18)) { self.turning = false }
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        LayoutMode.shared.mask
    }
}

/// One clear button that says where it takes you: "Portrait" with a turning phone in
/// landscape, "Landscape" upright. Stacked with its label on the landscape rail; a pill
/// with the word inside upright.
struct LayoutSwitch: View {
    /// Stacked for the landscape rail, side by side upright.
    var vertical = false

    var body: some View {
        let mode = LayoutMode.shared
        let target = mode.portrait ? "Landscape" : "Portrait"
        Button { mode.set(portrait: !mode.portrait) } label: {
            // HUD D, both layouts: a grey word like the toggles.
            Text(target)
                .font(.osData)
                .foregroundStyle(Palette.nightMuted)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, minHeight: vertical ? 30 : 44, alignment: vertical ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(target.lowercased()) layout")
    }
}
