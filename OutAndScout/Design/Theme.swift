import SwiftUI

// v2 design tokens. Source: the "App UI guidelines" board in the v2 design canvas.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum Palette {
    static let paper = Color(hex: 0xF3F3F0)
    static let ink = Color(hex: 0x111111)
    static let graphite = Color(hex: 0x66665F)
    /// Accent for the sun, the current time and the golden-hour window. Nothing else.
    static let sun = Color(hex: 0xFF5A1F)
    static let rule = Color(hex: 0xD9D9D3)
    /// Viewfinder background.
    static let night = Color(hex: 0x0B0B0A)
    /// Hairlines and chip borders on the dark viewfinder.
    static let nightRule = Color(hex: 0x2E2E2B)
    /// Secondary text on the dark viewfinder.
    static let nightMuted = Color(hex: 0x8A8A83)
    /// HUD backing: ink at 72%.
    static let hud = Color(hex: 0x111111, opacity: 0.72)
}

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let readout: CGFloat = 6
    static let card: CGFloat = 14
    static let viewfinder: CGFloat = 20
    static let sheet: CGFloat = 24
}

enum ButtonHeight {
    static let primary: CGFloat = 48
    static let secondary: CGFloat = 44
    static let chip: CGFloat = 30
}

extension Font {
    // E2 type: Geist 400 for words, Geist Mono only for numbers (lens, times, shot IDs,
    // degrees), so readouts hold still as they change. Small sizes, one weight.
    /// 13, a panel or scene title.
    static let osTitle = Fonts.sans(13, .regular)
    /// 12, button labels like "Export list".
    static let osAction = Fonts.sans(12, .regular)
    /// 12, a shot row title or caption.
    static let osRow = Fonts.sans(12, .regular)
    /// 11, supporting text.
    static let osSupport = Fonts.sans(11, .regular)
    /// 11, labels and readouts made of words.
    static let osData = Fonts.sans(11, .regular)
    /// 10, small labels (e.g. "Next").
    static let osDataSmall = Fonts.sans(10, .regular)
    /// 9, rail labels.
    static let osTiny = Fonts.sans(9, .regular)
    /// 11, numbers: "40mm · 08:02", shot IDs, counts.
    static let osNum = Fonts.mono(11)
    /// 10, small numbers.
    static let osNumSmall = Fonts.mono(10)
    /// 9, hour ticks.
    static let osNumTiny = Fonts.mono(9)
}

// MARK: - Buttons

/// Pill button. Primary is 56 tall and filled, secondary 44 and outlined.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary
    /// Light sheets use ink on paper; the viewfinder uses paper on ink.
    var onDark = false

    func makeBody(configuration: Configuration) -> some View {
        let fg = onDark ? Palette.ink : Palette.paper
        let bg = onDark ? Palette.paper : Palette.ink
        configuration.label
            .font(.osAction)
            .lineLimit(1)
            .fixedSize(horizontal: kind == .secondary, vertical: false)
            .padding(.horizontal, Space.xl)
            .frame(height: kind == .primary ? ButtonHeight.primary : ButtonHeight.secondary)
            .frame(maxWidth: kind == .primary ? .infinity : nil)
            .foregroundStyle(kind == .primary ? fg : bg)
            .background(kind == .primary ? bg : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .primary ? .clear : bg.opacity(0.4), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

/// 36-tall chip, used for aspect ratios and small toggles. Hit area is padded to 44.
struct Chip: View {
    let label: String
    var selected = false
    var onDark = true
    var mono = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(mono ? .osData : .osSupport)
                .padding(.horizontal, Space.s)
                .frame(height: ButtonHeight.chip)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .overlay(Capsule().strokeBorder(border, lineWidth: 1))
                .padding(.vertical, (44 - ButtonHeight.chip) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        if onDark { return selected ? Palette.ink : Palette.paper }
        return selected ? Palette.paper : Palette.ink
    }
    private var background: Color {
        if onDark { return selected ? Palette.paper : .clear }
        return selected ? Palette.ink : .clear
    }
    private var border: Color {
        if selected { return .clear }
        return onDark ? Palette.nightRule : Palette.rule
    }
}

/// Small light marker: a filled sun dot for golden-hour shots, a ring for any other light.
struct LightDot: View {
    let golden: Bool
    var size: CGFloat = 8

    var body: some View {
        Group {
            if golden {
                Circle().fill(Palette.sun)
            } else {
                Circle().strokeBorder(Palette.graphite, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(golden ? "golden hour" : "other light")
    }
}

/// Thin horizontal rule in the light sheets.
struct Rule: View {
    var color = Palette.rule
    var body: some View { color.frame(height: 1) }
}

/// A horizontal chip row that fades out at its right edge, so a chip cut off by the edge
/// reads as "more this way" rather than a stray sliver.
struct FadingHScroll<Content: View>: View {
    @ViewBuilder let content: Content
    /// Whether there's more to scroll to on each side; that side fades only then.
    @State private var more = (leading: false, trailing: true)
    private let fade: CGFloat = 24

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { content }
            // Room at both ends so the first and last chip sit clear of the fade.
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .onScrollGeometryChange(for: [Bool].self) { g in
                [g.contentOffset.x > -g.contentInsets.leading + 1,
                 g.contentOffset.x + g.containerSize.width < g.contentSize.width + g.contentInsets.trailing - 1]
            } action: { _, v in
                withAnimation(.easeOut(duration: 0.15)) { more = (v[0], v[1]) }
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [more.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fade)
                    Color.black
                    LinearGradient(colors: [.black, more.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: fade)
                }
            }
    }
}
