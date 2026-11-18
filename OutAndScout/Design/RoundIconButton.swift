import SwiftUI

/// An icon-only round button in the OPill outline style: a 44 pt circle with one SF Symbol.
/// Used where a word would crowd the row (rotate, info).
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.5, weight: .regular))
                .foregroundStyle(Palette.paper)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Outline.line, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(OPressRing())
        .accessibilityLabel(label)
    }
}

/// A bare SF Symbol button: no ring, muted, 44 pt hit area. Sits quietly beside the pills.
struct BareIconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 15
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(Sheet.muted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(OPressRing())
        .accessibilityLabel(label)
    }
}

/// Turns the layout between portrait and landscape for this screen only (not remembered).
/// Replaces the "↻ Portrait" / "↻ Landscape" words (Elliot, 18 Nov: "just a little arrow").
struct RotateButton: View {
    let portrait: Bool

    var body: some View {
        if !LayoutMode.isPad {
            BareIconButton(systemImage: "rotate.right",
                           label: portrait ? "Turn to landscape" : "Turn to portrait", size: 17) {
                LayoutMode.shared.set(portrait: !portrait, remember: false)
            }
        }
    }
}

/// The small "i" beside "Pin for shoot day" and on the pinned PDF.
struct ShootDayInfoButton: View {
    var body: some View {
        BareIconButton(systemImage: "info.circle", label: "How Shoot day works") {
            ShootDay.shared.showHowTo()
        }
    }
}
