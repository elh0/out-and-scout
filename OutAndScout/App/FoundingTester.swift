import StoreKit
import SwiftUI

/// Founding testers (Elliot, 16 Oct 2026): anyone who opens a TestFlight build is remembered,
/// and gets Pro free for good once Out & Scout launches. The reward is for testing, never for
/// a rating. TestFlight builds say so; the App Store build shows a claim card, switched off
/// until `code` is filled in at launch. Shared plan: eltio/apps/founding-tester/founding-tester-spec.md.
enum FoundingTester {
    static let key = "foundingTester.seenInBeta"
    /// The custom offer code (free Pro, ~50 redemptions, no end date). Empty until Apple lets us
    /// make it, after Pro is approved; filling it in is the only change needed at launch.
    static let code = ""
    /// The one-time Pro unlock. Placeholder until Pro is set up in App Store Connect.
    static let proProductID = "com.outandscout.app.pro"
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

    static func ownsPro() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == proProductID, tx.revocationDate == nil { return true }
        }
        return false
    }

    /// Launch: a tester on the App Store build who hasn't got Pro yet, once the code exists.
    static func shouldOfferClaim() async -> Bool {
        guard !code.isEmpty, isTester, !(await isBetaBuild()) else { return false }
        return !(await ownsPro())
    }

    /// The start screen shows the card until it's closed once; the Projects panel always does.
    static var startCardDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }
}

/// "Founding tester": a small card. In TestFlight builds it says Pro is coming (no button, no
/// code). In the App Store build, for testers only, it offers Pro with "Claim Pro", which opens
/// Apple's redeem sheet. The App Store version never mentions beta or TestFlight.
struct FoundingTesterCard: View {
    /// On the start screen it has a close mark and stays closed once closed.
    var dismissible = false
    private enum Mode { case none, coming, claim }
    @State private var mode = Mode.none
    @State private var dismissed = FoundingTester.startCardDismissed
    @State private var redeeming = false

    var body: some View {
        Group {
            if mode != .none && !(dismissible && dismissed) {
                HStack(alignment: .top, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 5) {
                        Caps(text: "Founding tester").foregroundStyle(Sheet.text)
                        Text(mode == .claim
                             ? "Thanks for scouting with us early. Pro is yours, free."
                             : "Thanks for scouting with us early. When Out & Scout launches, Pro is yours free, for good. The app will show you how to claim it, nothing to do now.")
                            .font(.osSans(12))
                            .foregroundStyle(Sheet.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if mode == .claim {
                            HStack(spacing: Space.s) {
                                OPill(label: "Claim Pro", on: true, size: .small) { redeeming = true }
                                Text("CODE \(FoundingTester.code)")
                                    .font(Fonts.mono(9))
                                    .tracking(0.6)
                                    .foregroundStyle(Sheet.muted)
                                    .textSelection(.enabled)
                            }
                            .padding(.top, 4)
                        }
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
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await refresh() }
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let next: Mode
        if await FoundingTester.isBetaBuild() {
            next = .coming
        } else if await FoundingTester.shouldOfferClaim() {
            next = .claim
        } else {
            next = .none
        }
        withAnimation(.easeOut(duration: 0.2)) { mode = next }
    }
}
