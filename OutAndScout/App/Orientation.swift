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

/// Portrait | landscape, as two icons in one outlined pill. The picked one is filled.
struct LayoutSwitch: View {
    /// Stacked for the landscape rail, side by side upright.
    var vertical = false

    var body: some View {
        let mode = LayoutMode.shared
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        VStack(spacing: 4) {
            layout {
                option("rectangle.portrait", "portrait", on: mode.portrait) { mode.set(portrait: true) }
                option("rectangle", "landscape", on: !mode.portrait) { mode.set(portrait: false) }
            }
            .padding(2)
            .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
            if vertical {
                Text("Layout").font(.osTiny).foregroundStyle(Palette.nightMuted)
            }
        }
    }

    private func option(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(on ? Palette.ink : Palette.paper.opacity(0.8))
                .frame(width: 30, height: 28)
                .background(on ? Palette.paper : .clear, in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
