import SwiftUI

/// The locked name: "Out & Sc●out", Geist 400, the sun raised in the word. One lockup for
/// the opening, the Projects panel and the start screen. `rise` 0…1 animates the sun from
/// just below its place (and invisible) into it.
struct Wordmark: View {
    var size: CGFloat = 17
    var rise: CGFloat = 1

    var body: some View {
        // Word spacing .3em on top of a normal space (~.25em).
        HStack(alignment: .firstTextBaseline, spacing: size * 0.55) {
            Text("Out")
            Text("&")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Sc")
                Circle()
                    .fill(Palette.sun)
                    .frame(width: size * 0.22, height: size * 0.22)
                    .padding(.leading, size * 0.45)
                    .padding(.trailing, size * 0.5)
                    // Raised .55em; while rising it starts .4em lower.
                    .offset(y: -size * 0.55 + (1 - rise) * size * 0.4)
                    .opacity(min(1, rise * 4))
                Text("out")
            }
        }
        .font(Fonts.sans(size, .regular))
        .tracking(-0.03 * size)
        .foregroundStyle(Palette.paper)
        .fixedSize()
        .accessibilityElement()
        .accessibilityLabel("Out & Scout")
    }
}

/// The opening (prototype option D): the wordmark fades in on ink and the sun rises a
/// little from the middle of the letters into its place. Covers the camera's start-up.
struct LaunchMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var rise: CGFloat = 0

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            Wordmark(size: 30, rise: rise)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            if reduceMotion {
                rise = 1
                withAnimation(.easeOut(duration: 0.35)) { shown = true }
                return
            }
            withAnimation(.easeOut(duration: 0.35)) { shown = true }
            withAnimation(.timingCurve(0.25, 0.6, 0.2, 1, duration: 1.0).delay(0.25)) { rise = 1 }
        }
    }
}
