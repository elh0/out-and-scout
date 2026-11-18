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

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// Paper by day, night by night: follows the view's light or dark look.
    static func look(day: UInt32, night: UInt32, dayAlpha: CGFloat = 1, nightAlpha: CGFloat = 1) -> UIColor {
        UIColor { t in
            t.userInterfaceStyle == .dark ? UIColor(hex: night, alpha: nightAlpha) : UIColor(hex: day, alpha: dayAlpha)
        }
    }
}

extension Color {
    /// A token with a paper (day) and a night value. Which one shows follows the colour scheme,
    /// so the 1.1 Paper look and the old dark look share every view.
    static func look(day: UInt32, night: UInt32, dayOpacity: Double = 1, nightOpacity: Double = 1) -> Color {
        Color(uiColor: .look(day: day, night: night, dayAlpha: dayOpacity, nightAlpha: nightOpacity))
    }
}

// 1.1 "Paper" (Elliot, 18 Nov 2026): the whole app on warm paper with ink, one orange.
// Night keeps the 1.0 outline look. The names are the 1.0 names, so "paper" is the
// foreground (ink on paper by day, paper on night by night) and "night" the background.
// The 1.0 design is kept at the git tag design-1.0-outline.
enum Palette {
    /// Foreground on the screen: ink by day, paper by night.
    static let paper = Color.look(day: 0x151513, night: 0xF3F3F0)
    /// The opposite of `paper`: text on a filled `paper` capsule.
    static let ink = Color.look(day: 0xF1EEE7, night: 0x111111)
    static let graphite = Color.look(day: 0x8A877F, night: 0x66665F)
    /// Accent for the sun, the current time and the golden-hour window. Nothing else.
    static let sun = Color.look(day: 0xE2531F, night: 0xFF5A1F)
    static let rule = Color.look(day: 0xCFCBC2, night: 0xD9D9D3)
    /// Viewfinder background: paper by day.
    static let night = Color.look(day: 0xF1EEE7, night: 0x0B0B0A)
    static let nightUI = UIColor.look(day: 0xF1EEE7, night: 0x0B0B0A)
    /// Hairlines and chip borders on the viewfinder.
    static let nightRule = Color.look(day: 0xCFCBC2, night: 0x2E2E2B)
    /// Secondary text on the viewfinder.
    static let nightMuted = Color.look(day: 0x8A877F, night: 0x8A8A83)
    /// HUD backing over the picture: ink at 72%, day or night.
    static let hud = Color(hex: 0x111111, opacity: 0.72)
    /// Lines, words and marks drawn on the live picture or a photo: always light, day or night.
    static let onPicture = Color(hex: 0xF3F3F0)
    /// Dark backing for words on the picture.
    static let onPictureInk = Color(hex: 0x111111)
}

/// Sheets (Shot List, Export, Projects, Kit): paper by day, the 1.0 grey-black by night.
enum Sheet {
    static let bg = Color.look(day: 0xF1EEE7, night: 0x121211)
    static let text = Color.look(day: 0x151513, night: 0xECEBE6)
    static let muted = Color.look(day: 0x8A877F, night: 0x8C8A83)
    static let rule = Color.look(day: 0xCFCBC2, night: 0x2A2926)
}

/// The outline look's hairlines and cards, on paper by day.
enum Outline {
    /// Pill and card edges.
    static let line = Color.look(day: 0x151513, night: 0xECEBE6, dayOpacity: 0.35, nightOpacity: 0.42)
    /// Sheets and cards that sit over the screen.
    static let card = Color.look(day: 0xEAE6DE, night: 0x1A1A19)
    /// The ring a pill or card gets while pressed.
    static let ring = Color.look(day: 0x151513, night: 0xECEBE6, dayOpacity: 0.12, nightOpacity: 0.16)
}

/// A hairline pill: outlined, or filled paper when on. Hit area padded to 44.
struct OPill: View {
    enum Size { case small, regular, big }
    let label: String
    var on = false
    var size: Size = .regular
    var caps = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(caps ? label.uppercased() : label)
                .font(Fonts.mono(size == .big ? 11 : 10))
                .tracking(0.4)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(on ? Sheet.bg : Palette.paper)
                .padding(.horizontal, size == .small ? 8 : size == .big ? 18 : 11)
                .frame(minWidth: size == .small ? 34 : 38, minHeight: height)
                .background(on ? Sheet.text : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Sheet.text : Outline.line, lineWidth: 1))
                .padding(.vertical, max(0, (44 - height) / 2))
                .contentShape(Rectangle())
        }
        .buttonStyle(OPressRing())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var height: CGFloat { (size == .small ? 22 : size == .big ? 34 : 26) * Fonts.scale }
}

/// Pressed: a soft ring and a touch of fade, like the prototype's hover ring.
struct OPressRing: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A tick box: hairline square when off; filled paper with a dark tick when on, so "on" reads
/// at a glance (Elliot, 18 Nov: Frames, Sun and Notes looked unticked).
struct TickBox: View {
    let on: Bool
    var round = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: round ? 8 : 4)
        shape
            .fill(on ? Sheet.text : .clear)
            .overlay(shape.strokeBorder(on ? Sheet.text : Outline.line, lineWidth: 1))
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Sheet.bg)
                }
            }
            .frame(width: 16, height: 16)
    }
}

/// A small caps label, like "EXPORT" or "OTHER PROJECTS".
struct Caps: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.osDataSmall)
            .tracking(1.2)
    }
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
    // Type (Elliot, 6 Oct 2026): Geist Mono everywhere in the app, one weight, small sizes.
    // Only the "Out & Sc●out" wordmark stays in Geist. The osNum names are kept for numbers.
    /// 13, a panel or scene title.
    static let osTitle = Fonts.mono(13)
    /// 12, button labels like "Export list".
    static let osAction = Fonts.mono(12)
    /// 12, a shot row title or caption.
    static let osRow = Fonts.mono(12)
    /// 11, supporting text.
    static let osSupport = Fonts.mono(11)
    /// 11, labels and readouts.
    static let osData = Fonts.mono(11)
    /// 10, small labels (e.g. "Next").
    static let osDataSmall = Fonts.mono(10)
    /// 9, rail labels.
    static let osTiny = Fonts.mono(9)
    /// 11, numbers: "40mm · 08:02", shot IDs, counts.
    static let osNum = Fonts.mono(11)
    /// 10, small numbers.
    static let osNumSmall = Fonts.mono(10)
    /// 9, hour ticks.
    static let osNumTiny = Fonts.mono(9)

    /// Outline look: Geist for names, titles and the big lens number.
    static func osSans(_ size: CGFloat) -> Font { Fonts.sans(size, .regular) }
}

// MARK: - Buttons

/// Pill button. Primary is 56 tall and filled, secondary 44 and outlined.
struct PillButtonStyle: ButtonStyle {
    /// outline: the one bordered button on an E2 sheet. text: an underlined word.
    enum Kind { case primary, secondary, outline, text }
    var kind: Kind = .primary
    /// Light sheets use ink on paper; the viewfinder uses paper on ink.
    var onDark = false

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        switch kind {
        case .outline:
            configuration.label
                .font(.osTitle)
                .lineLimit(1)
                .foregroundStyle(Sheet.text)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .overlay(Rectangle().strokeBorder(Sheet.text, lineWidth: 1))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        case .text:
            configuration.label
                .font(.osRow)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Sheet.text)
                .underline(color: Sheet.muted)
                .frame(minHeight: 44)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(Rectangle())
        default:
            pill(configuration)
        }
    }

    private func pill(_ configuration: Configuration) -> some View {
        let fg = onDark ? Palette.ink : Palette.paper
        let bg = onDark ? Palette.paper : Palette.ink
        return configuration.label
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
    /// E2 sheets: a plain word, underlined when picked, grey when not. No capsule.
    var underline = false
    let action: () -> Void

    var body: some View {
        if underline {
            Button(action: action) {
                Text(label)
                    .font(.osRow)
                    .foregroundStyle(selected ? Sheet.text : Sheet.muted)
                    .underline(selected, color: Sheet.text)
                    .fixedSize()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            capsule
        }
    }

    private var capsule: some View {
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
    var color = Sheet.rule
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

// MARK: - Day and night (1.1 Paper)

/// Paper by day; the viewfinder and the photo viewer switch to the 1.0 dark look from sunset
/// to sunrise, so the screen never glares at night. "Night" in the ··· menu picks it by hand.
@MainActor @Observable final class Look {
    static let shared = Look()

    enum Mode: String, CaseIterable {
        case auto, day, night
        var label: String {
            switch self {
            case .auto: "Auto"
            case .day: "Day"
            case .night: "Night"
            }
        }
    }

    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "look.mode") }
    }

    private init() {
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: "look.mode") ?? "") ?? .auto
    }

    /// Day, then night, then auto.
    func cycle() {
        mode = switch mode {
        case .auto: .day
        case .day: .night
        case .night: .auto
        }
    }

    /// Night once the sun's top edge has gone (sunset), until it's back (sunrise).
    func isNight(sunElevation: Double) -> Bool {
        switch mode {
        case .day: false
        case .night: true
        case .auto: sunElevation < -0.83
        }
    }
}

/// Gives its content the night look when it's dark out (checked each minute), paper otherwise.
struct NightAware<Content: View>: View {
    @Environment(LocationService.self) private var location
    @State private var look = Look.shared
    @ViewBuilder let content: Content

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let c = location.coordinate
            let sun = SunCalculator.position(at: tl.date, latitude: c.latitude, longitude: c.longitude)
            content
                .environment(\.colorScheme, look.isNight(sunElevation: sun.elevation) ? .dark : .light)
        }
    }
}

// MARK: - 1.1 Paper kit: tabs, the big number, the light chip, the live strip

/// The four places in the app, along the top of every paper screen.
enum PaperTab: String, CaseIterable {
    case camera = "Camera", shots = "Shots", selects = "Selects", export = "Export"
}

/// CAMERA · SHOTS · SELECTS · EXPORT, the current one in ink with an orange underline.
struct PaperTabs: View {
    let current: PaperTab
    var disabled: Set<PaperTab> = []
    let go: (PaperTab) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(PaperTab.allCases, id: \.self) { t in
                let on = t == current
                Button { if !on { go(t) } } label: {
                    Text(t.rawValue.uppercased())
                        .font(Fonts.mono(10))
                        .tracking(0.8)
                        .foregroundStyle(on ? Sheet.text : Sheet.muted)
                        .padding(.bottom, 4)
                        .overlay(alignment: .bottom) { if on { Palette.sun.frame(height: 1.5) } }
                        .fixedSize()
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled.contains(t))
                .opacity(disabled.contains(t) ? 0.4 : 1)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// One big orange number with a rule and a label under it: the first thing on a paper screen.
struct BigNumber: View {
    let value: String
    let label: String
    var trailing: String? = nil
    var size: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(Fonts.sans(size, .medium))
                .tracking(-size * 0.03)
                .foregroundStyle(Palette.sun)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Palette.sun.frame(height: 1.5)
            HStack(spacing: 6) {
                Text(label.uppercased()).lineLimit(1)
                Spacer(minLength: 0)
                if let trailing { Text(trailing.uppercased()).lineLimit(1) }
            }
            .font(Fonts.mono(9))
            .tracking(0.8)
            .foregroundStyle(Sheet.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// B / ¾B / S / ¾F / F, shaded from solid (backlit) to an outline (front lit).
struct LightChip: View {
    let light: LightClass?

    var body: some View {
        let fill: Double = switch light {
        case .backlit: 1
        case .threeQuarterBack: 0.62
        case .side: 0.3
        case .threeQuarterFront: 0.12
        case .front, .none: 0
        }
        Text(light?.letter ?? "–")
            .font(Fonts.mono(9))
            .foregroundStyle(fill > 0.5 ? Sheet.bg : Sheet.text)
            .frame(minWidth: 24, minHeight: 16)
            .padding(.horizontal, 2)
            .background(Sheet.text.opacity(fill))
            .overlay(Rectangle().strokeBorder(Sheet.text.opacity(light == nil ? 0.3 : 1), lineWidth: 1))
            .accessibilityLabel(light?.title ?? "no heading")
    }
}


/// The foot of a paper screen: where the sun is now and today's golden hour. MORE ▴ opens
/// sunrise, sunset and the weather.
struct LiveStrip: View {
    @Environment(LocationService.self) private var location
    var more: (() -> Void)? = nil

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let c = location.coordinate
            let sun = SunCalculator.position(at: tl.date, latitude: c.latitude, longitude: c.longitude)
            let day = SunCalculator.day(containing: tl.date, latitude: c.latitude, longitude: c.longitude)
            let golden = day.goldenWindows.first { $0.upperBound > tl.date } ?? day.goldenWindows.last
            HStack(spacing: 14) {
                Text("SUN \(Int(sun.azimuth.rounded()))° · \(Int(sun.elevation.rounded()))°")
                    .foregroundStyle(Sheet.text)
                if let golden {
                    Text("GOLDEN \(Format.time(golden.lowerBound))–\(Format.time(golden.upperBound))")
                        .foregroundStyle(Palette.sun)
                }
                Spacer(minLength: 0)
                if let more {
                    Button(action: more) {
                        Text("MORE ▴").foregroundStyle(Sheet.muted)
                            .frame(minHeight: 36).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("sunrise, sunset and weather")
                }
            }
            .font(Fonts.mono(9))
            .tracking(0.6)
            .lineLimit(1)
            .frame(minHeight: 30)
            .overlay(alignment: .top) { Sheet.rule.frame(height: 1) }
        }
    }
}
