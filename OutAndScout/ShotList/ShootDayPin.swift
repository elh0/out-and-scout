import Observation
import PDFKit
import SwiftUI
import UIKit

/// Shoot day (18 Nov 2026): one PDF pinned for the day (an Out & Scout shot list or anyone's
/// call sheet), opened from a lock-screen button in one press. Free, not Pro.
@MainActor @Observable
final class ShootDay {
    static let shared = ShootDay()

    /// The pinned file's name as shown ("Rooftop shot list"), or nil when nothing's pinned.
    private(set) var pinnedName: String?
    /// The full-screen PDF is up.
    var showing = false
    /// The card showing how to add the lock-screen button. Comes up on every pin until
    /// "Don't show again", and any time from the pinned PDF's "How to" button.
    var showingHowTo = false

    private static let nameKey = "shootDayPinnedName"
    private static let howToOffKey = "shootDayHowToOff"

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shootday", isDirectory: true)
    }
    static var fileURL: URL { folder.appendingPathComponent("pinned.pdf") }

    private init() {
        let name = UserDefaults.standard.string(forKey: Self.nameKey)
        pinnedName = FileManager.default.fileExists(atPath: Self.fileURL.path) ? name ?? "Shoot day" : nil
    }

    /// Pins a copy of the PDF at `url` (replacing the last one). Returns false if it isn't a
    /// readable PDF.
    @discardableResult
    func pin(fileAt url: URL, name: String? = nil) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), PDFDocument(data: data) != nil else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return false }
        let shown = name ?? url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        pinnedName = shown
        UserDefaults.standard.set(shown, forKey: Self.nameKey)
        // Files that came in from another app land in Documents/Inbox; tidy that copy away.
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        if !UserDefaults.standard.bool(forKey: Self.howToOffKey) { showingHowTo = true }
        return true
    }

    func unpin() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        pinnedName = nil
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        showing = false
    }

    func showHowTo() { showingHowTo = true }

    func hideHowTo() { showingHowTo = false }

    /// "Don't show again": pins stop bringing the card up. "How to" still opens it.
    func howToOff() {
        UserDefaults.standard.set(true, forKey: Self.howToOffKey)
        showingHowTo = false
    }

    /// The lock-screen button was pressed: show the PDF, or say there isn't one.
    func openFromButton(toast: (String) -> Void) {
        if pinnedName != nil { showing = true } else { toast("Nothing pinned yet. Pin a PDF from Export.") }
    }
}

/// The pinned PDF, full screen. Pinch to zoom and scroll through pages (PDFKit), Unpin,
/// and Close back to wherever you were.
struct ShootDayViewer: View {
    let shootDay: ShootDay
    @State private var confirmUnpin = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHOOT DAY").font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
                    Text(shootDay.pinnedName ?? "").font(.osSans(15)).lineLimit(1)
                }
                Spacer()
                ShootDayInfoButton()
                OPill(label: "Unpin", caps: true) { confirmUnpin = true }
                OPill(label: "Close", on: true, caps: true) { shootDay.showing = false }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xs)
            PinnedPDF(url: ShootDay.fileURL)
        }
        .foregroundStyle(Sheet.text)
        .background(Sheet.bg.ignoresSafeArea())
        .confirmationDialog("Unpin \(shootDay.pinnedName ?? "this PDF")?", isPresented: $confirmUnpin, titleVisibility: .visible) {
            Button("Unpin", role: .destructive) { shootDay.unpin() }
        } message: {
            Text("The lock-screen button will have nothing to open until you pin another.")
        }
    }
}

private struct PinnedPDF: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(Sheet.bg)
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}
}

/// Shown after a pin (until "Don't show again") and from the "i": how to put the button on the
/// lock screen (iOS doesn't let apps add it themselves). Approved design (Elliot, 18 Nov): a quiet
/// line-drawn phone acting out one step at a time, the step as one line of text underneath (beside
/// it in landscape), four progress ticks, and Got it as the only filled button.
struct ShootDayHowTo: View {
    let shootDay: ShootDay
    @Environment(\.isPortrait) private var portrait
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demo = LockDemoState()

    private static let lines = [
        "Hold your lock screen",
        "Tap Customise, then Lock Screen",
        "Remove the torch with −",
        "Tap +, then choose Shoot day",
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { shootDay.hideHowTo() }
                card(width: portrait ? 300 : geo.size.width * 0.88)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .task { await demo.run(still: reduceMotion) }
    }

    private func card(width: CGFloat) -> some View {
        Group {
            if portrait {
                VStack(spacing: 26) {
                    LineDrawnPhone(state: demo, width: 112, still: reduceMotion)
                    copy(alignment: .center)
                }
                .padding(EdgeInsets(top: 28, leading: 24, bottom: 20, trailing: 24))
            } else {
                HStack(alignment: .center, spacing: 40) {
                    LineDrawnPhone(state: demo, width: 96, still: reduceMotion)
                    copy(alignment: .leading)
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 28)
            }
        }
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Outline.card))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Sheet.text.opacity(0.14), lineWidth: 1))
        .foregroundStyle(Sheet.text)
    }

    private func copy(alignment: HorizontalAlignment) -> some View {
        let text: TextAlignment = alignment == .center ? .center : .leading
        let frameAlign: Alignment = alignment == .center ? .center : .leading
        return VStack(alignment: alignment, spacing: 10) {
            Text("LOCK-SCREEN BUTTON · \(demo.step + 1) OF 4")
                .font(Fonts.mono(9)).tracking(1.1).foregroundStyle(Sheet.muted)
                .contentTransition(.numericText())
            // One line per step; two lines of height kept so nothing jumps.
            ZStack(alignment: frameAlign) {
                Text("A\nB").font(Fonts.sans(portrait ? 19 : 21, .medium)).hidden()
                Text(Self.lines[demo.step])
                    .font(Fonts.sans(portrait ? 19 : 21, .medium))
                    .tracking(-0.3)
                    .multilineTextAlignment(text)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(demo.step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: frameAlign)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i <= demo.step ? Palette.sun : Sheet.text.opacity(0.14))
                        .frame(width: 18, height: 2)
                }
            }
            HStack {
                Button { shootDay.howToOff() } label: {
                    Text("DON'T SHOW AGAIN").font(Fonts.mono(10)).foregroundStyle(Sheet.muted)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 12)
                Button { shootDay.hideHowTo() } label: {
                    Text("GOT IT").font(Fonts.mono(11)).tracking(1.1)
                        .foregroundStyle(Color.black)
                        .padding(.vertical, 12).padding(.horizontal, 20)
                        .background(Palette.sun, in: Capsule())
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(OPressRing())
            }
            .padding(.top, 6)
        }
        .animation(.easeInOut(duration: 0.35), value: demo.step)
    }
}

/// Where the demo is: which step, whether the fingertip is down, and whether that step's tap
/// has happened (its result showing).
@MainActor @Observable
final class LockDemoState {
    var step = 0
    var pressing = false
    var done = false

    /// Reduce Motion: step through the text only, no fingertip or movement.
    func run(still: Bool = false) async {
        if still {
            while !Task.isCancelled {
                guard await pause(2.6) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { step = (step + 1) % 4; done = false; pressing = false }
            }
            return
        }
        while !Task.isCancelled {
            for s in 0..<4 {
                withAnimation(.spring(duration: 0.55, bounce: 0.15)) { step = s; done = false; pressing = false }
                guard await pause(0.7) else { return }
                withAnimation(.spring(duration: 0.3)) { pressing = true }
                // The first step is a hold; the rest are taps.
                guard await pause(s == 0 ? 1.0 : 0.3) else { return }
                withAnimation(.spring(duration: 0.55, bounce: 0.12)) { pressing = false; done = true }
                guard await pause(s == 3 ? 2.0 : 1.1) else { return }
            }
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }
}

/// The approved quiet line drawing of a phone (not a realistic iPhone): 9:19.5, 1 pt outline,
/// Dynamic Island, a dark lock screen with date, time and Apple's two round buttons, acting out:
/// 0 a fingertip holds the centre; 1 the lock screen shrinks into Customise; 2 a − badge on the
/// torch and the torch goes; 3 the Controls sheet slides up, Shoot day is tapped, and it lands
/// bottom-left as a sun circle.
private struct LineDrawnPhone: View {
    let state: LockDemoState
    let width: CGFloat
    var still = false

    // Drawn at 112 wide and scaled, so landscape (96) keeps the same proportions.
    private let W: CGFloat = 112
    private var H: CGFloat { W * 19.5 / 9 }
    private let inset: CGFloat = 4
    private var SW: CGFloat { W - inset * 2 }
    private var SH: CGFloat { H - inset * 2 }

    private var step: Int { state.step }
    private var done: Bool { state.done }
    private var customise: Bool { step == 1 && !still }
    private var torchGone: Bool { !still && ((step == 2 && done) || step == 3) }
    private var sheetUp: Bool { !still && step == 3 && !done }
    private var shootDayIn: Bool { !still && step == 3 && done }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Outline.line, lineWidth: 1)
            screen
                .frame(width: SW, height: SH)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(width: W, height: H)
        .scaleEffect(width / W)
        .frame(width: width, height: width * 19.5 / 9)
        .accessibilityHidden(true)
    }

    private var screen: some View {
        ZStack(alignment: .top) {
            Color(hex: 0x0A0A0A)
            lockScreen
                .clipShape(RoundedRectangle(cornerRadius: customise ? 14 : 0, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(customise ? 0.5 : 0), lineWidth: 1))
                .scaleEffect(customise ? 0.74 : 1)
                .offset(y: customise ? -SH * 0.08 : 0)

            if customise {
                Text("Customise")
                    .font(Fonts.sans(6.5, .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3.5)
                    .background(.white.opacity(0.16), in: Capsule())
                    .offset(y: SH - 30)
                    .transition(.opacity)
            }

            controlsSheet
                .offset(y: sheetUp ? SH * 0.44 : SH + 4)

            // Dynamic Island.
            Capsule().fill(.black).frame(width: 28, height: 8).padding(.top, 7 - inset)

            if !still { fingertip }
        }
    }

    private var lockScreen: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: Color(hex: 0x17181C), location: 0),
                .init(color: Color(hex: 0x221E1F), location: 0.62),
                .init(color: Color(hex: 0x3A2218), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Text("WED 18 NOV")
                .font(Fonts.mono(6)).tracking(0.4)
                .foregroundStyle(.white.opacity(0.75))
                .padding(.top, 25 - inset)
            Text("9:41")
                .font(Fonts.sans(22, .medium)).tracking(-0.66)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 33 - inset)
            HStack {
                leftButton
                Spacer()
                roundButton("camera.fill")
            }
            .padding(.horizontal, 11 - inset)
            .padding(.bottom, 12 - inset)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: SW, height: SH)
    }

    @ViewBuilder private var leftButton: some View {
        if shootDayIn {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 9)).foregroundStyle(.black)
                .frame(width: 19, height: 19)
                .background(Palette.sun, in: Circle())
                .transition(.scale.combined(with: .opacity))
        } else if torchGone {
            Circle().strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
                .frame(width: 19, height: 19)
                .transition(.opacity)
        } else {
            roundButton("flashlight.off.fill")
                .overlay(alignment: .topLeading) {
                    if step == 2 && !still {
                        Image(systemName: "minus")
                            .font(.system(size: 5, weight: .heavy)).foregroundStyle(.black)
                            .frame(width: 8, height: 8)
                            .background(.white, in: Circle())
                            .offset(x: -2.5, y: -2.5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    private func roundButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9)).foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
            .background(Circle().fill(Color(hex: 0x3A3A3A, opacity: 0.55)))
    }

    private var controlsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 16, height: 2)
                .frame(maxWidth: .infinity).padding(.top, 5).padding(.bottom, 6)
            row("flashlight.off.fill", "Torch", sun: false)
            row("plus.forwardslash.minus", "Calculator", sun: false)
            row("doc.text.fill", "Shoot day · Out & Scout", sun: true)
            row("timer", "Timer", sun: false)
            Spacer(minLength: 0)
        }
        .frame(width: SW, height: SH * 0.56, alignment: .top)
        .background(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
            .fill(Color(hex: 0x1C1C1B)))
    }

    private func row(_ symbol: String, _ name: String, sun: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 6)).foregroundStyle(sun ? Color.black : .white)
                .frame(width: 12, height: 12)
                .background(RoundedRectangle(cornerRadius: 3).fill(sun ? Palette.sun : .white.opacity(0.14)))
            Text(name).font(Fonts.sans(6, .medium)).foregroundStyle(.white.opacity(sun ? 1 : 0.7))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 3.5)
        .background(RoundedRectangle(cornerRadius: 5)
            .fill(sun && state.pressing && step == 3 ? Palette.sun.opacity(0.18) : .clear))
        .padding(.horizontal, 4)
    }

    /// Fingertip position for each step, in the screen's coordinates (top-left origin).
    private var fingerAt: CGPoint {
        switch step {
        case 0: return CGPoint(x: SW / 2, y: SH * 0.52)
        case 1: return CGPoint(x: SW / 2, y: SH - 30 + 7)
        case 2: return CGPoint(x: 11 - inset + 9.5, y: SH - (12 - inset) - 9.5)
        default: return CGPoint(x: SW * 0.42, y: SH * 0.44 + 13 + 2 * 19 + 9)
        }
    }

    private var fingertip: some View {
        Circle()
            .fill(.white.opacity(0.12))
            .overlay(Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1))
            .frame(width: 20, height: 20)
            .scaleEffect(state.pressing ? 0.85 : 1)
            .opacity(done && !state.pressing ? 0 : 1)
            .position(fingerAt)
            .frame(width: SW, height: SH, alignment: .topLeading)
    }
}
