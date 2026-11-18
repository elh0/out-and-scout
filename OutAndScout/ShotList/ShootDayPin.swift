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
    /// The one-time card showing how to add the lock-screen button.
    var showingHowTo = false

    private static let nameKey = "shootDayPinnedName"
    private static let howToKey = "shootDayHowToSeen"

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
        if !UserDefaults.standard.bool(forKey: Self.howToKey) { showingHowTo = true }
        return true
    }

    func unpin() {
        try? FileManager.default.removeItem(at: Self.fileURL)
        pinnedName = nil
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        showing = false
    }

    func howToSeen() {
        UserDefaults.standard.set(true, forKey: Self.howToKey)
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

/// Shown once after the first pin: how to put the button on the lock screen (iOS doesn't
/// let apps add it themselves).
struct ShootDayHowTo: View {
    let shootDay: ShootDay

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { shootDay.howToSeen() }
            VStack(alignment: .leading, spacing: 12) {
                Text("PINNED · \((shootDay.pinnedName ?? "").uppercased())")
                    .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Sheet.muted).lineLimit(1)
                Text("Add the lock-screen button").font(.osSans(18))
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Hold the lock screen")
                    step(2, "Customise › Lock Screen")
                    step(3, "Tap the left button (the torch) and remove it")
                    step(4, "Tap +, then Out & Scout › Shoot day")
                }
                Text("Then one press opens this PDF, after Face ID. Pin a new one any time from Export, or Share › Out & Scout from Mail or WhatsApp.")
                    .font(.osDataSmall).foregroundStyle(Sheet.muted)
                    .fixedSize(horizontal: false, vertical: true)
                OPill(label: "Got it", on: true, size: .big, caps: true) { shootDay.howToSeen() }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(18)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 18).fill(Outline.card))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Outline.line, lineWidth: 1.5))
            .foregroundStyle(Sheet.text)
            .padding(Space.m)
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Fonts.mono(10)).foregroundStyle(Palette.sun)
            Text(text).font(.osData)
        }
    }
}
