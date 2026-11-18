import StoreKit
import SwiftUI

/// Out & Scout Pro (18 Nov 2026): one purchase, no subscription. Free gets the whole app
/// with one project and a credit line on PDFs; Pro is unlimited projects and clean PDFs.
/// The price shown always comes from the App Store, so changing it there needs no build.
@MainActor @Observable
final class Pro {
    static let shared = Pro()

    /// Free keeps everything, with one project.
    static let freeProjects = 1

    private(set) var owned = false
    private(set) var product: Product?
    private(set) var busy = false
    /// Why the paywall is up ("Unlimited projects"), or nil when it's down.
    var paywallReason: String?
    var redeeming = false
    var message: String?

    private var updates: Task<Void, Never>?

    private init() {
        owned = UserDefaults.standard.bool(forKey: "pro.owned")
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.refresh()
                }
            }
        }
        Task { await refresh() }
    }

    /// Price as the App Store shows it in your country ("£19.99"), or nil before it loads.
    var price: String? { product?.displayPrice }

    /// Reads what's been bought and loads the product. Cheap; call on launch and foreground.
    func refresh() async {
        if product == nil {
            product = try? await Product.products(for: [FoundingTester.proProductID]).first
        }
        let has = await FoundingTester.ownsPro()
        owned = has
        UserDefaults.standard.set(has, forKey: "pro.owned")
    }

    /// Shows the paywall when free hits a limit; returns true if the thing can go ahead.
    func allow(_ reason: String) -> Bool {
        if owned { return true }
        paywallReason = reason
        return false
    }

    func buy() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        message = nil
        if product == nil { await refresh() }
        guard let product else { message = "Can't reach the App Store. Try again in a moment."; return }
        do {
            switch try await product.purchase() {
            case .success(let result):
                if case .verified(let tx) = result { await tx.finish() }
                await refresh()
                if owned { paywallReason = nil; message = nil }
            case .pending:
                message = "Waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. Try again."
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        if owned { paywallReason = nil; message = nil } else { message = "No Pro purchase found on this Apple ID." }
    }
}

/// The Pro card, over everything: what it adds, the price, Buy, Restore, Redeem code.
struct ProPaywall: View {
    let pro: Pro

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { pro.paywallReason = nil }
            VStack(alignment: .leading, spacing: 14) {
                Text((pro.paywallReason ?? "Out & Scout Pro").uppercased())
                    .font(Fonts.mono(9)).tracking(0.6).foregroundStyle(Palette.sun)
                Text("Out & Scout Pro").font(.osSans(22))
                VStack(alignment: .leading, spacing: 7) {
                    line("Unlimited projects")
                    line("Clean PDFs, without the Out & Scout credit line")
                    line("One payment. No subscription.")
                }
                Text("Free keeps every feature with one project.")
                    .font(.osDataSmall).foregroundStyle(Sheet.muted)
                if let message = pro.message {
                    Text(message).font(.osDataSmall).foregroundStyle(Sheet.text)
                }
                OPill(label: pro.busy ? "One moment…" : "Get Pro" + (pro.price.map { " · \($0)" } ?? ""), on: true, size: .big, caps: true) {
                    Task { await pro.buy() }
                }
                .frame(maxWidth: .infinity)
                .disabled(pro.busy)
                HStack(spacing: 6) {
                    OPill(label: "Restore", size: .small, caps: true) { Task { await pro.restore() } }
                    OPill(label: "Redeem code", size: .small, caps: true) { pro.redeeming = true }
                    Spacer()
                    OPill(label: "Not now", size: .small, caps: true) { pro.paywallReason = nil }
                }
            }
            .padding(20)
            .frame(maxWidth: 380)
            .background(RoundedRectangle(cornerRadius: 18).fill(Outline.card))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Outline.line, lineWidth: 1.5))
            .foregroundStyle(Sheet.text)
            .padding(Space.m)
        }
        .offerCodeRedemption(isPresented: Binding(get: { pro.redeeming }, set: { pro.redeeming = $0 })) { _ in
            Task { await pro.refresh(); if pro.owned { pro.paywallReason = nil } }
        }
        .task { await pro.refresh() }
    }

    private func line(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(Palette.sun).frame(width: 5, height: 5).offset(y: -2)
            Text(text).font(.osData)
        }
    }
}
