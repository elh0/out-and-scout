import SwiftUI

// The upright Viewfinder, outline look round 4 (locked 8 Oct 2026). Top to bottom: Projects
// and the time; the scene, which way you face and the layout switch; the scenes as pills;
// the white frame window; ratio pills; the light now with sun path, grid and level; the
// day's line; the big lens number and its pills; then Shots, the shutter and the kit.

/// "Projects" on the left, the time on the right (orange "→ 17:40" once moved; tap for now).
struct PortraitTopRow: View {
    @Environment(ScoutStore.self) private var store
    let planned: Date

    var body: some View {
        HStack {
            Button { store.panel = .projects } label: {
                Text("Projects")
                    .font(Fonts.mono(11))
                    .foregroundStyle(Palette.paper)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("opens your projects")

            Spacer()

            let moved = store.plannedMinutes != nil
            Button { store.plannedMinutes = nil } label: {
                Text(moved ? "→ \(Format.time(planned))" : Format.time(Date()))
                    .font(Fonts.mono(11))
                    .foregroundStyle(moved ? Palette.sun : Sheet.muted)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!moved)
            .accessibilityLabel(moved ? "planned for \(Format.time(planned)), tap for now" : "now, \(Format.time(Date()))")
        }
    }
}

/// "KNOLE PARK · FACING SOUTH-WEST" in grey caps, the layout switch on the right.
struct PortraitCompassRow: View {
    @Environment(ScoutStore.self) private var store
    let heading: Double?
    let headingAccuracy: Double?
    let sunAzimuth: Double

    var body: some View {
        HStack {
            Text(crumb)
                .font(Fonts.mono(10))
                .tracking(0.6)
                .foregroundStyle(Sheet.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Space.s)
            LayoutSwitch()
        }
    }

    private var crumb: String {
        var s = store.currentScene.name
        if let heading { s += " · facing \(Bearing.facing(heading))" }
        return s.uppercased()
    }
}

/// This project's scenes as small pills (tap to switch), then "+" for a new one.
struct PortraitScenesRow: View {
    @Environment(ScoutStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(store.currentProject.scenes) { scene in
                        OPill(label: scene.name, on: scene.id == store.currentSceneID, size: .small) {
                            store.select(project: store.currentProjectID, scene: scene.id)
                        }
                        .id(scene.id)
                    }
                    OPill(label: "+", size: .small) { store.requestNewScene() }
                        .accessibilityLabel("new scene here")
                }
            }
            .onAppear { proxy.scrollTo(store.currentSceneID, anchor: .center) }
            .onChange(of: store.currentSceneID) { proxy.scrollTo(store.currentSceneID, anchor: .center) }
        }
    }
}

/// The upright ratios as pills.
struct PortraitToolsRow: View {
    /// Upright work needs fewer ratios: tall ones for social, square, and 16:9.
    static let ratios: [AspectRatio] = [
        .vertical,
        AspectRatio(value: 4.0 / 5.0, label: "4:5"),
        AspectRatio(value: 1, label: "1:1"),
        .hd,
    ]

    var body: some View {
        HStack {
            RatioPills(ratios: Self.ratios)
            Spacer(minLength: 0)
        }
    }
}

/// "11:08 · SIDE LIT · LEFT" (orange in golden hour), Sun, Grid and Level on the right, then
/// the day's line.
struct PortraitTimeRow: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    let sunDay: SunDay?
    let planned: Date
    let sun: SunPosition

    var body: some View {
        let golden = sunDay?.goldenWindows.contains { $0.contains(planned) } ?? false
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                Text("\(Format.time(planned)) · \(read)".uppercased())
                    .font(Fonts.mono(10))
                    .tracking(0.6)
                    .foregroundStyle(golden ? Palette.sun : Sheet.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: Space.xs)
                word("Sun", on: store.overlays.sunPath) { store.toggle(\.sunPath) }
                word("Grid", on: store.overlays.grid) { store.toggle(\.grid) }
                word("Level", on: store.overlays.level) { store.toggle(\.level) }
            }
            SunTimeline(sunDay: sunDay, planned: planned)
        }
    }

    private var read: String {
        guard sun.elevation > -1 else { return "Sun down" }
        guard let h = motion.heading ?? location.heading else { return "Sun \(Int(sun.elevation.rounded()))° up" }
        return LightClass.readShort(rel: LightRead.rel(sunAzimuth: sun.azimuth, heading: h))
    }

    private func word(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(Fonts.mono(10))
                .tracking(0.6)
                .foregroundStyle(on ? Palette.paper : Sheet.muted)
                .padding(.leading, 12)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "Sun" ? "sun path" : label.lowercased())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The big lens number (swipe left or right), its pills, then Shots, the shutter and the kit.
struct PortraitBottomRow: View {
    @Environment(ScoutStore.self) private var store
    let capturing: Bool
    let onShutter: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            BigLens(vertical: false)
            LensPills(vertical: false)
            ZStack {
                HStack {
                    ShotStack(beside: true)
                    Spacer()
                    Button { store.panel = .kit } label: {
                        Text(store.kit.camera.name.uppercased())
                            .font(Fonts.mono(10))
                            .tracking(0.6)
                            .foregroundStyle(Sheet.muted)
                            .lineLimit(1)
                            .frame(maxWidth: 110, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("kit, \(store.kit.label)")
                }
                Shutter(capturing: capturing, action: onShutter)
            }
            .padding(.top, 6)
        }
    }
}
