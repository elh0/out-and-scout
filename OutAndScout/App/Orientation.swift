import SwiftUI
import UIKit

/// The layout is picked with a button ("turn sideways" / "turn upright"), not by tilting
/// the phone. Landscape still flips between its two sides; it never drops into portrait.
enum Orientation {
    private static let key = "upright"

    /// What the app allows right now; read by the app delegate.
    static var mask: UIInterfaceOrientationMask =
        UserDefaults.standard.bool(forKey: key) ? .portrait : .landscape

    static var isUpright: Bool { mask == .portrait }

    /// Switches the layout and turns the screen to match.
    static func set(upright: Bool, remember: Bool = true) {
        mask = upright ? .portrait : .landscape
        if remember { UserDefaults.standard.set(upright, forKey: key) }
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
        Orientation.mask
    }
}

/// "turn sideways" from the v3c Portrait board: 28 high, outlined, 10pt.
struct TurnSidewaysButton: View {
    var onDark = true

    var body: some View {
        Button { Orientation.set(upright: false) } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.landscape.rotate").font(.system(size: 10))
                Text("turn sideways")
            }
            .font(.osDataSmall)
            .foregroundStyle(onDark ? Palette.paper : Palette.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .overlay(Capsule().strokeBorder(onDark ? Palette.nightRule : Palette.rule, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
