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

/// Shown after a pin (until "Don't show again") and from the info button: how to put the
/// button on the lock screen (iOS doesn't let apps add it themselves). A drawn iPhone acts the
/// four steps out on a loop, and the step it's on lights up in the list. Upright the phone sits
/// above the steps; in landscape it sits beside them so nothing is squashed.
struct ShootDayHowTo: View {
    let shootDay: ShootDay
    @Environment(\.isPortrait) private var portrait
    @State private var demo = LockDemoState()

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { shootDay.hideHowTo() }
            card
                .padding(portrait ? Space.m : Space.s)
        }
        .task { await demo.run() }
    }

    private var card: some View {
        Group {
            if portrait {
                VStack(alignment: .leading, spacing: 16) {
                    title
                    LockScreenDemo(state: demo, height: 300).frame(maxWidth: .infinity)
                    steps
                    buttons
                }
                .frame(maxWidth: 360)
            } else {
                HStack(alignment: .center, spacing: 24) {
                    LockScreenDemo(state: demo, height: 290)
                    VStack(alignment: .leading, spacing: 16) {
                        title
                        steps
                        Spacer(minLength: 0)
                        buttons
                    }
                    .frame(width: 300)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22).fill(Outline.card))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Outline.line.opacity(0.5), lineWidth: 1))
        .foregroundStyle(Sheet.text)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SHOOT DAY").font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted)
            Text("Add the lock-screen button").font(.osSans(18))
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 9) {
            row(0, "Hold the lock screen")
            row(1, "Tap Customise, then Lock Screen")
            row(2, "Remove the torch with −")
            row(3, "Tap +, pick Shoot day")
            Text("One press then opens your pinned PDF.")
                .font(.osDataSmall).foregroundStyle(Sheet.muted)
                .padding(.top, 2)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            OPill(label: "Don't show again", size: .small, caps: true) { shootDay.howToOff() }
            Spacer(minLength: 8)
            OPill(label: "Got it", on: true, size: .big, caps: true) { shootDay.hideHowTo() }
        }
    }

    private func row(_ n: Int, _ text: String) -> some View {
        let on = demo.step == n
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n + 1)").font(Fonts.mono(10)).foregroundStyle(on ? Palette.sun : Sheet.muted)
            Text(text).font(.osData).foregroundStyle(on ? Sheet.text : Sheet.muted)
        }
        .animation(.easeOut(duration: 0.25), value: demo.step)
    }
}

/// Where the demo is: which step, whether the fingertip is down, and whether that step's tap
/// has happened (its result showing).
@MainActor @Observable
final class LockDemoState {
    var step = 0
    var pressing = false
    var done = false

    func run() async {
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

/// A drawn iPhone (19.5:9, thin even bezel, Dynamic Island) on its lock screen, acting out:
/// 0 a fingertip holds the screen; 1 the lock screen shrinks into its frame with Customise
/// underneath; 2 edit mode, − badges on the two buttons, the torch goes; 3 the Controls gallery
/// slides up, "Shoot day · Out & Scout" is tapped, and it lands bottom-left.
private struct LockScreenDemo: View {
    let state: LockDemoState
    /// The phone's height; everything is drawn at 300 and scaled.
    var height: CGFloat

    private let H: CGFloat = 300
    private var W: CGFloat { H * 9 / 19.5 }
    private let bezel: CGFloat = 5

    var body: some View {
        phone
            .frame(width: W, height: H)
            .scaleEffect(height / H)
            .frame(width: W * height / H, height: height)
            .accessibilityHidden(true)
    }

    private var step: Int { state.step }
    private var done: Bool { state.done }
    /// Customise mode: the lock screen sits small inside the frame.
    private var shrunk: Bool { step == 1 && !done || (step == 1 && done) }
    private var editing: Bool { step == 2 || step == 3 }
    private var galleryUp: Bool { step == 3 && !done }
    private var torchGone: Bool { (step == 2 && done) || step == 3 }
    private var shootDayIn: Bool { step == 3 && done }

    private var phone: some View {
        let outer = RoundedRectangle(cornerRadius: 44, style: .continuous)
        let inner = RoundedRectangle(cornerRadius: 44 - bezel, style: .continuous)
        return ZStack {
            outer.fill(Color(hex: 0x050505))
            outer.strokeBorder(LinearGradient(colors: [Color(hex: 0x5A5A56), Color(hex: 0x2A2A28)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing),
                               lineWidth: 1.2)
            screen
                .clipShape(inner)
                .padding(bezel)
        }
    }

    private var screen: some View {
        ZStack {
            Color.black
            // The lock screen itself, shrunk into a card in Customise.
            lockScreen
                .clipShape(RoundedRectangle(cornerRadius: shrunk ? 22 : 0, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(shrunk ? 0.5 : 0), lineWidth: 1))
                .scaleEffect(shrunk ? 0.72 : 1)
                .offset(y: shrunk ? -18 : 0)

            if shrunk {
                Text("Customise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(.white.opacity(0.18), in: Capsule())
                    .offset(y: 112)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }

            gallery
                .offset(y: galleryUp ? 52 : 200)
                .opacity(galleryUp ? 1 : 0)

            // Dynamic Island, always on top.
            Capsule().fill(.black)
                .frame(width: 58, height: 17)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 7)

            fingertip
        }
    }

    private var lockScreen: some View {
        ZStack {
            // Soft wallpaper: dusk, warm low on the screen.
            LinearGradient(stops: [
                .init(color: Color(hex: 0x1C1F2A), location: 0),
                .init(color: Color(hex: 0x3A3036), location: 0.55),
                .init(color: Palette.sun.opacity(0.55), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                Text("Wednesday 18 November")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text("9:41")
                    .font(.system(size: 62, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.top, -2)
                Spacer()
            }
            .padding(.top, 34)

            HStack {
                corner(left: true)
                Spacer()
                corner(left: false)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func corner(left: Bool) -> some View {
        let symbol: String? = left ? (shootDayIn ? "doc.text" : torchGone ? nil : "flashlight.off.fill") : "camera.fill"
        ZStack(alignment: .topLeading) {
            ZStack {
                Circle().fill(.white.opacity(symbol == nil ? 0.06 : 0.16))
                if symbol == nil {
                    Circle().strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5]))
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Image(systemName: symbol!).font(.system(size: 13)).foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                }
                if left && shootDayIn {
                    Circle().strokeBorder(Palette.sun, lineWidth: 1.5)
                }
            }
            .frame(width: 34, height: 34)
            // − badges in edit mode, while there's something to remove.
            if editing && symbol != nil && !(left && shootDayIn) {
                Image(systemName: "minus")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 15, height: 15)
                    .background(Color(hex: 0xD9D9D6), in: Circle())
                    .offset(x: -4, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    /// The Controls gallery: a sheet with a search field and the Shoot day control.
    private var gallery: some View {
        VStack(alignment: .leading, spacing: 9) {
            Capsule().fill(.white.opacity(0.3)).frame(width: 30, height: 4).frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 9))
                Text("Search controls").font(.system(size: 9))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 8).frame(height: 22)
            .background(.white.opacity(0.1), in: Capsule())
            Text("OUT & SCOUT").font(Fonts.mono(7)).tracking(0.5).foregroundStyle(.white.opacity(0.5))
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 13)).foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Shoot day").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                    Text("Out & Scout").font(.system(size: 8)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(state.pressing && step == 3 ? 0.2 : 0.1)))
            HStack(spacing: 8) {
                ForEach(["timer", "qrcode", "moon"], id: \.self) { s in
                    Image(systemName: s).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.08), in: Circle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: W - bezel * 2, height: 200, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(hex: 0x1E1E1E)))
    }

    /// Where the fingertip goes for each step, from the screen's centre.
    private var fingerAt: CGPoint {
        switch step {
        case 0: return CGPoint(x: 6, y: 40)
        case 1: return CGPoint(x: 0, y: 112)
        case 2: return CGPoint(x: -(W - bezel * 2) / 2 + 22 + 17 - 4, y: (H - bezel * 2) / 2 - 20 - 17 - 4)
        default: return CGPoint(x: -20, y: 22)
        }
    }

    private var fingertip: some View {
        let showing = !done || state.pressing
        return ZStack {
            Circle().fill(.white.opacity(0.35))
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
            // A ring that spreads while the finger holds.
            Circle().strokeBorder(.white.opacity(state.pressing ? 0 : 0.5), lineWidth: 1)
                .scaleEffect(state.pressing ? 1.9 : 1)
        }
        .frame(width: 26, height: 26)
        .scaleEffect(state.pressing ? 0.82 : 1)
        .opacity(showing ? 1 : 0)
        .offset(x: fingerAt.x, y: fingerAt.y)
    }
}
