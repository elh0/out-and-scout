import SwiftUI

/// The locked name: "Out & Sc●out", Geist 400, the sun raised in the word. One lockup for
/// the opening, the Projects panel and the start screen.
struct Wordmark: View, Animatable {
    var size: CGFloat = 17
    /// 0 to 1. At 0 the letters sit together and the sun is hidden low in the gap; as it
    /// grows the letters part where the light falls and the sun rises into its place
    /// (the identity page's "part" animation).
    var rise: CGFloat = 1

    // Animatable, so the Canvas redraws every frame while `rise` changes.
    var animatableData: CGFloat {
        get { rise }
        set { rise = newValue }
    }

    // The lockup, in ems: sun .22 wide, raised .55, .45 before and .5 after it.
    private static let sun: CGFloat = 0.22
    private static let raised: CGFloat = 0.55
    /// Ascent above the baseline the drawing allows for (the sun's top is at .77).
    private static let top: CGFloat = 0.8

    var body: some View {
        // Drawn from Geist's outlines rather than typed, so it can never fall back to
        // another face, and the gap can open as the sun rises.
        let r = max(0, min(1, rise))
        let before = 0.03 + (0.45 - 0.03) * r
        let after = 0.03 + (0.5 - 0.03) * r
        let width = WordmarkGlyphs.leftWidth + before + Self.sun + after + WordmarkGlyphs.rightWidth
        let height = Self.top + WordmarkGlyphs.descent
        Canvas { ctx, _ in
            var c = ctx
            c.scaleBy(x: size, y: size)
            c.translateBy(x: 0, y: Self.top)
            c.fill(WordmarkGlyphs.left, with: .color(Palette.paper))
            let sunX = WordmarkGlyphs.leftWidth + before
            // Starts .45em lower, as on the identity page.
            let sunY = -Self.raised - Self.sun + (1 - r) * 0.45
            var s = c
            s.opacity = min(1, r / 0.4)
            s.fill(Path(ellipseIn: CGRect(x: sunX, y: sunY, width: Self.sun, height: Self.sun)),
                   with: .color(Palette.sun))
            c.translateBy(x: sunX + Self.sun + after, y: 0)
            c.fill(WordmarkGlyphs.right, with: .color(Palette.paper))
        }
        .frame(width: width * size, height: height * size)
        .alignmentGuide(.firstTextBaseline) { _ in Self.top * size }
        .alignmentGuide(.lastTextBaseline) { _ in Self.top * size }
        .accessibilityElement()
        .accessibilityLabel("Out & Scout")
        .accessibilityAddTraits(.isHeader)
    }
}

/// The opening (prototype option D): the wordmark fades in on ink, the letters part and
/// the sun rises into its place. Covers the camera's start-up.
struct LaunchMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the first frame showed; the animation is worked out from the clock, so it
    /// plays even if the camera starting up drops a few frames.
    @State private var start: Date?

    var body: some View {
        ZStack {
            Palette.night.ignoresSafeArea()
            TimelineView(.animation(paused: start == nil)) { context in
                let t = start.map { context.date.timeIntervalSince($0) } ?? 0
                // Fades in over .35 s; from .2 s the letters part and the sun rises over
                // 1.8 s, easing out (the identity page's timing).
                let fade = min(1, max(0, t / 0.35))
                let p = min(1, max(0, (t - 0.2) / 1.8))
                let rise = reduceMotion ? 1 : 1 - pow(1 - p, 3)
                Wordmark(size: 30, rise: CGFloat(rise))
                    .opacity(start == nil ? 0 : (reduceMotion ? 1 : fade))
            }
        }
        // A .task, not onAppear: onAppear can fire while iOS's own launch screen still
        // covers the app. A short wait lets the first frame show before the clock starts.
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            start = Date()
        }
    }
}
