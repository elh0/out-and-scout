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
                OPill(label: "How to", caps: true) { shootDay.showHowTo() }
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

/// Shown after a pin (until "Don't show again") and from "How to": how to put the button on
/// the lock screen (iOS doesn't let apps add it themselves). A small looping picture of a lock
/// screen plays the four steps, and the step it's on lights up in the list.
struct ShootDayHowTo: View {
    let shootDay: ShootDay
    @State private var step = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { shootDay.hideHowTo() }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let name = shootDay.pinnedName {
                        Text("PINNED · \(name.uppercased())")
                            .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted).lineLimit(1)
                    }
                    Text("Add the lock-screen button").font(.osSans(18))
                    LockScreenDemo(step: step)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        row(0, "Hold the lock screen")
                        row(1, "Customise › Lock Screen")
                        row(2, "Tap − on the left button (the torch)")
                        row(3, "Tap +, then Out & Scout › Shoot day")
                    }
                    Text("Then one press opens this PDF, after Face ID. Pin a new one any time from Export, or Share › Out & Scout from Mail or WhatsApp. This card is under How to on the pinned PDF.")
                        .font(.osDataSmall).foregroundStyle(Sheet.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        OPill(label: "Don't show again", caps: true) { shootDay.howToOff() }
                        Spacer()
                        OPill(label: "Got it", on: true, size: .big, caps: true) { shootDay.hideHowTo() }
                    }
                }
                .padding(18)
                .frame(maxWidth: 380)
                .background(RoundedRectangle(cornerRadius: 18).fill(Outline.card))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Outline.line, lineWidth: 1.5))
                .foregroundStyle(Sheet.text)
                .padding(Space.m)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        .task {
            // About 2 s a step, round and round while the card is up.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(.easeInOut(duration: 0.45)) { step = (step + 1) % 4 }
            }
        }
    }

    private func row(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n + 1)").font(Fonts.mono(10)).foregroundStyle(Palette.sun)
            Text(text).font(.osData)
        }
        .opacity(step == n ? 1 : 0.45)
    }
}

/// A line drawing of a lock screen acting out one step: 0 a finger holds the screen,
/// 1 the Customise button, 2 the torch button with its − badge, 3 the Shoot day button in its place.
private struct LockScreenDemo: View {
    let step: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26).fill(Color.black)
            RoundedRectangle(cornerRadius: 26).strokeBorder(Outline.line, lineWidth: 1.5)
            VStack(spacing: 2) {
                Text("Wed 18").font(Fonts.mono(8)).foregroundStyle(Palette.paper.opacity(0.7))
                Text("9:41").font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.paper)
            }
            .scaleEffect(step == 1 ? 0.86 : 1)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 22)

            // Step 0: a finger holding the middle of the screen.
            Circle()
                .fill(Palette.paper.opacity(0.25))
                .overlay(Circle().strokeBorder(Palette.paper.opacity(0.8), lineWidth: 1.5))
                .frame(width: 34, height: 34)
                .scaleEffect(step == 0 ? 1 : 0.4)
                .opacity(step == 0 ? 1 : 0)
                .offset(y: 18)

            // Step 1: the Customise button.
            Text("Customise")
                .font(Fonts.mono(9))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Palette.paper, in: Capsule())
                .opacity(step == 1 ? 1 : 0)
                .offset(y: step == 1 ? 40 : 52)

            // Bottom corners: the left button changes; the camera stays.
            HStack {
                leftButton
                Spacer()
                corner(Image(systemName: "camera.fill"))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: 150, height: 250)
    }

    private var leftButton: some View {
        ZStack(alignment: .topLeading) {
            corner(Image(systemName: step == 3 ? "doc.text" : "flashlight.off.fill"))
                .overlay(Circle().strokeBorder(Palette.sun, lineWidth: step >= 2 ? 1.5 : 0))
            Image(systemName: step == 3 ? "plus" : "minus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 14, height: 14)
                .background(Palette.paper, in: Circle())
                .offset(x: -3, y: -3)
                .opacity(step == 2 ? 1 : 0)
        }
    }

    private func corner(_ image: Image) -> some View {
        image
            .font(.system(size: 13))
            .foregroundStyle(Palette.paper)
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.14), in: Circle())
            .contentTransition(.opacity)
    }
}
