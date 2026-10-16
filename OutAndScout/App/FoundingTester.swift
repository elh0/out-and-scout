import StoreKit
import SwiftUI

/// Founding testers (Elliot, 16 Oct 2026): anyone who opens a TestFlight build is remembered,
/// and gets Pro free for good once Out & Scout launches. The reward is for testing, never for
/// a rating. For now the app only remembers and says so; the claim card comes with the launch
/// build, once the offer code exists. Shared plan: eltio/apps/founding-tester/founding-tester-spec.md.
enum FoundingTester {
    static let key = "foundingTester.seenInBeta"
    private static let dismissedKey = "foundingTester.startCardDismissed"

    /// Call once at launch. Installing the App Store build over a TestFlight one keeps this flag.
    static func markIfBeta() async {
        if await isBetaBuild() { UserDefaults.standard.set(true, forKey: key) }
    }

    static var isTester: Bool { UserDefaults.standard.bool(forKey: key) }

    /// TestFlight (sandbox) or Xcode, never the App Store.
    static func isBetaBuild() async -> Bool {
        guard let result = try? await AppTransaction.shared, case .verified(let tx) = result else { return false }
        return tx.environment != .production
    }

    /// The start screen shows the card until it's closed once; the Projects panel always does.
    static var startCardDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }
}

/// "Founding tester": a small card, only in TestFlight builds. No button and no code yet.
struct FoundingTesterCard: View {
    /// On the start screen it has a close mark and stays closed once closed.
    var dismissible = false
    @State private var beta = false
    @State private var dismissed = FoundingTester.startCardDismissed

    var body: some View {
        Group {
            if beta && !(dismissible && dismissed) {
                HStack(alignment: .top, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 5) {
                        Caps(text: "Founding tester").foregroundStyle(Sheet.text)
                        Text("Thanks for scouting with us early. When Out & Scout launches, Pro is yours free, for good. The app will show you how to claim it, nothing to do now.")
                            .font(.osSans(12))
                            .foregroundStyle(Sheet.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if dismissible {
                        Spacer(minLength: 0)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                            FoundingTester.startCardDismissed = true
                        } label: {
                            Text("×").font(Fonts.mono(13)).foregroundStyle(Sheet.muted)
                                .frame(width: 32, height: 32).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("close")
                    }
                }
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Outline.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Outline.line, lineWidth: 1))
                .transition(.opacity)
            }
        }
        .task { beta = await FoundingTester.isBetaBuild() }
    }
}
