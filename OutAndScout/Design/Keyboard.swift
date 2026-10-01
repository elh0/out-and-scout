import SwiftUI
import UIKit

/// The app ignores the keyboard so nothing gets shoved about when it appears.
/// Scrolling lists use this instead, so a row being renamed near the bottom
/// can still scroll up into view above the keyboard.
struct KeyboardPadding: ViewModifier {
    @Environment(ScoutStore.self) private var store
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // The floating name bar sits above the keyboard on its own. Padding here as well
            // would make the panel taller than the screen and shove everything up.
            .safeAreaPadding(.bottom, store.rename == nil ? height : 0)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
                else { return }
                height = max(0, screen.bounds.maxY - end.minY)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                height = 0
            }
    }
}

extension View {
    func keyboardPadding() -> some View { modifier(KeyboardPadding()) }
}
