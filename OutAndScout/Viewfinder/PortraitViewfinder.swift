import SwiftUI

// The upright Viewfinder. Built on the v3c Portrait board, with the same tools as the
// landscape Viewfinder: project / scene, clock and kit; + scene, compass and the layout
// switch; the frame; sun path, grid, level and a few upright ratios; time, light and the
// sun timeline; then shots, the shutter and the lens dial.

private enum PortraitInk {
    static let muted = Palette.nightMuted
    static let soft = Color(hex: 0xB5B5AE)
    static let faint = Color(hex: 0x45453F)
}

/// HUD D upright: "Projects", then "project / scene", the clock and kit pills on the right.
struct PortraitTopRow: View {
    @Environment(ScoutStore.self) private var store
    let planned: Date

    var body: some View {
        HStack(spacing: Space.s) {
            Button { store.panel = .projects } label: {
                Text("Projects")
                    .font(.osData)
                    .foregroundStyle(Palette.paper)
                    .underline(color: PortraitInk.muted)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint("opens your projects")

            Button { store.panel = .projects } label: {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(TopBar.short(store.currentProject.name, max: 10)).foregroundStyle(PortraitInk.muted)
                        .fixedSize()
                    Text("/").foregroundStyle(PortraitInk.muted)
                    Text(store.currentScene.name).foregroundStyle(Palette.paper)
                }
                .font(.osData)
                .lineLimit(1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(store.currentProject.name), \(store.currentScene.name)")
            .accessibilityHint("opens your projects")

            Spacer(minLength: Space.xs)

            // Tap to snap back to now.
            Button { store.plannedMinutes = nil } label: {
                // Just the time: white for now, orange when scrubbed.
                Text(Format.time(store.plannedMinutes == nil ? Date() : planned))
                .font(.osNum)
                .foregroundStyle(store.plannedMinutes == nil ? Palette.paper : Palette.sun)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint("back to now")

            Button { store.panel = .kit } label: {
                Text(store.kit.label)
                    .font(.osData)
                    .foregroundStyle(Palette.paper)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 110)
            .accessibilityLabel("kit, \(store.kit.label)")
        }
    }
}

/// The compass in the middle, the layout switch as a word on the right.
struct PortraitCompassRow: View {
    @Environment(ScoutStore.self) private var store
    let heading: Double?
    let headingAccuracy: Double?
    let sunAzimuth: Double

    var body: some View {
        ZStack {
            HStack {
                Spacer()
                LayoutSwitch()
            }
            CompassTape(heading: heading, accuracy: headingAccuracy, sunAzimuth: sunAzimuth)
                .frame(width: 140, height: 26)
        }
    }
}

/// HUD D's Scenes column laid on its side: this project's scenes (tap to switch), + Scene.
struct PortraitScenesRow: View {
    @Environment(ScoutStore.self) private var store

    var body: some View {
        HStack(spacing: Space.m) {
            Caps(text: "Scenes").foregroundStyle(PortraitInk.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    ForEach(store.currentProject.scenes) { scene in
                        let current = scene.id == store.currentSceneID
                        Button { store.select(project: store.currentProjectID, scene: scene.id) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(scene.name).font(.osData)
                                    .foregroundStyle(current ? Palette.paper : PortraitInk.muted)
                                    .underline(current, color: Palette.paper)
                                Text("\(scene.shots.count)").font(.osNumTiny).foregroundStyle(PortraitInk.muted)
                            }
                            .lineLimit(1)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(current ? [.isSelected] : [])
                    }
                    Button { store.requestNewScene() } label: {
                        Text("+ Scene").font(.osData).foregroundStyle(Palette.paper)
                            .frame(minHeight: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("new scene here")
                }
            }
        }
    }
}

/// Sun path, grid and level as words (lit and underlined when on), then the upright ratios.
struct PortraitToolsRow: View {
    @Environment(ScoutStore.self) private var store

    /// Upright work needs fewer ratios: tall ones for social, square, and 16:9.
    static let ratios: [AspectRatio] = [
        .vertical,
        AspectRatio(value: 4.0 / 5.0, label: "4:5"),
        AspectRatio(value: 1, label: "1:1"),
        .hd,
    ]

    var body: some View {
        HStack(spacing: Space.s) {
            RailToggle(symbol: "sun.horizon", label: "Sun Path", on: store.overlays.sunPath) { store.toggle(\.sunPath) }
            RailToggle(symbol: "grid", label: "Grid", on: store.overlays.grid) { store.toggle(\.grid) }
            RailToggle(symbol: "level", label: "Level", on: store.overlays.level) { store.toggle(\.level) }
            Spacer(minLength: 4)
            ForEach(Self.ratios) { a in
                let selected = a.label == store.aspect.label
                // Tap the picked ratio again to see the whole frame.
                Button { store.setAspect(selected ? .full : a) } label: {
                    Text(a.label)
                        .font(.osData)
                        .foregroundStyle(selected ? Palette.ink : Palette.paper)
                        .padding(.horizontal, 7)
                        .frame(height: 28)
                        .background(selected ? Palette.paper : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(selected ? Palette.paper : Palette.nightRule, lineWidth: 1))
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Time, the sun's height and the light, over the same sun timeline as landscape.
struct PortraitTimeRow: View {
    let sunDay: SunDay?
    let planned: Date
    let sun: SunPosition

    var body: some View {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: planned)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let light = LightPhase.from(elevation: sun.elevation, localHour: hour)

        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(Format.time(planned)).font(Fonts.mono(13)).foregroundStyle(Palette.paper)
                (Text("Sun ") + Text("\(Int(sun.elevation.rounded()))°").font(.osNumSmall)).font(.osDataSmall).foregroundStyle(PortraitInk.muted)
                Spacer()
                LightDot(golden: light == .goldenHour, size: 6)
                Text(light.label).font(.osData).foregroundStyle(PortraitInk.soft).lineLimit(1)
            }
            SunTimeline(sunDay: sunDay, planned: planned)
        }
    }
}

/// Shots on the left, the shutter in the middle, the lens dial on the right.
struct PortraitBottomRow: View {
    @Environment(ScoutStore.self) private var store
    let capturing: Bool
    let onShutter: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ShotStack()
                .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Button(action: onShutter) {
                    ZStack {
                        Circle().strokeBorder(Palette.paper, lineWidth: 3).frame(width: 72, height: 72)
                        Circle().fill(Palette.paper).frame(width: 58, height: 58)
                            .scaleEffect(capturing ? 0.85 : 1)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(capturing)
                .accessibilityLabel("pin as shot \(store.nextShotNumber)")
                .animation(.easeOut(duration: 0.12), value: capturing)
                (Text("Next ") + Text(store.nextShotNumber).font(.osNumSmall)).font(.osDataSmall).foregroundStyle(PortraitInk.muted)
            }

            PortraitLensDial()
                .frame(maxWidth: .infinity)
        }
    }
}

/// The lens wheel laid on its side: wider focal on the left, longer on the right, the
/// current one big in the middle with "mm" and the phone's zoom. Tap the sides or the
/// middle, or drag left and right.
struct PortraitLensDial: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    @State private var dragNotches = 0

    var body: some View {
        let focals = store.focalLengths
        let i = focals.firstIndex { $0 >= store.lensMM } ?? 0
        let next = i + 1 < focals.count ? focals[i + 1] : nil
        let prev = i > 0 ? focals[i - 1] : nil

        HStack(spacing: 4) {
            Button { store.stepLens(-1) } label: {
                Text(prev.map(Format.mm) ?? " ")
                    .font(.osNumSmall).foregroundStyle(PortraitInk.faint)
                    .frame(width: 26, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(prev == nil)
            .accessibilityLabel("wider lens")

            VStack(spacing: 0) {
                Text(Format.mm(store.lensMM)).font(Fonts.mono(20)).foregroundStyle(Palette.paper)
                HStack(spacing: 4) {
                    Text("mm").foregroundStyle(PortraitInk.muted)
                    Text(camera.lensLabel)
                        .foregroundStyle(camera.cropIsSoft ? PortraitInk.faint : Palette.paper.opacity(0.8))
                        .padding(.horizontal, 4)
                        .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                }
                .font(.osDataSmall)
            }
            .frame(minWidth: 56)

            Button { store.stepLens(1) } label: {
                Text(next.map(Format.mm) ?? " ")
                    .font(.osNumSmall).foregroundStyle(PortraitInk.faint)
                    .frame(width: 26, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(next == nil)
            .accessibilityLabel("longer lens")
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onChanged { v in
                    let notches = Int((v.translation.width / 28).rounded(.towardZero))
                    if notches != dragNotches {
                        store.stepLens(notches - dragNotches)
                        dragNotches = notches
                    }
                }
                .onEnded { _ in dragNotches = 0 }
        )
        .sensoryFeedback(.selection, trigger: store.focalLengths.lastIndex { $0 <= store.lensMM + 0.01 })
        .accessibilityElement(children: .contain)
        .accessibilityLabel("lens \(Format.mm(store.lensMM)) millimetres, iphone \(camera.lensLabel)")
    }
}
