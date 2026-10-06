import SwiftUI

/// The opening: the sun rises into its place in the mark on ink, the name types in under it,
/// then it all fades to the viewfinder once the camera is up. Covers the camera's start-up.
struct LaunchMark: View {
    @State private var risen = false
    @State private var named = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.42
            ZStack {
                Palette.night.ignoresSafeArea()
                VStack(spacing: side * 0.12) {
                    // The app icon's square: the sun high and off centre (64%, 36%, r 9%).
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        Circle()
                            .fill(Palette.sun)
                            .frame(width: side * 0.18, height: side * 0.18)
                            .position(x: side * 0.64, y: side * (risen ? 0.36 : 0.92))
                            .opacity(risen ? 1 : 0)
                    }
                    .frame(width: side, height: side)
                    .clipped()

                    name
                        .font(Fonts.sans(17, .regular))
                        .foregroundStyle(Palette.paper)
                        .opacity(named ? 1 : 0)
                        .offset(y: named ? 0 : 6)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { risen = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) { named = true }
        }
        .accessibilityElement()
        .accessibilityLabel("Out & Scout")
    }

    /// "Out & Sc◦out": the sun sits raised in the word, like the locked name.
    private var name: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Out  &  Sc")
            Circle()
                .fill(Palette.sun)
                .frame(width: 4, height: 4)
                .padding(.horizontal, 4)
                .offset(y: -8)
            Text("out")
        }
    }
}
