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

/// "night shift / brick lane" on the left, the clock pill on the right.
struct PortraitTopRow: View {
    @Environment(ScoutStore.self) private var store
    let planned: Date

    var body: some View {
        HStack {
            // Tap for projects and scenes; the names rename in landscape and in Projects.
            Button { store.panel = .projects } label: {
                HStack(spacing: 6) {
                    Text("\(store.currentProject.name) /").foregroundStyle(PortraitInk.muted)
                    Text(store.currentScene.name).foregroundStyle(Palette.paper)
                }
                .font(.osRow)
                .lineLimit(1)
                .padding(.horizontal, 4)
                .frame(height: 36)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("projects and scenes")

            Spacer(minLength: Space.xs)

            // Tap to snap back to now.
            Button { store.plannedMinutes = nil } label: {
                // Just the time: white for now, orange when scrubbed.
                Text(Format.time(store.plannedMinutes == nil ? Date() : planned))
                .font(.osData)
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

/// "+ scene" on the left, the compass in the middle, portrait | landscape on the right.
struct PortraitCompassRow: View {
    @Environment(ScoutStore.self) private var store
    let heading: Double?
    let headingAccuracy: Double?
    let sunAzimuth: Double

    var body: some View {
        ZStack {
            HStack {
                Button { store.requestNewScene() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold))
                        Text("Scene")
                    }
                    .font(.osData)
                    .foregroundStyle(Palette.paper)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("new scene here")
                Spacer()
                LayoutSwitch()
            }
            CompassTape(heading: heading, accuracy: headingAccuracy, sunAzimuth: sunAzimuth)
                .frame(width: 140, height: 26)
        }
    }
}

/// Sun path, grid and level as small round toggles, then the upright ratios.
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
        HStack(spacing: 6) {
            toggle("sun.horizon", "sun path", on: store.overlays.sunPath) { store.toggle(\.sunPath) }
            toggle("grid", "grid", on: store.overlays.grid) { store.toggle(\.grid) }
            toggle("level", "level", on: store.overlays.level) { store.toggle(\.level) }
            Spacer(minLength: 4)
            ForEach(Self.ratios) { a in
                let selected = a.label == store.aspect.label
                // Tap the picked ratio again to see the whole frame.
                Button { store.setAspect(selected ? .full : a) } label: {
                    Text(a.label)
                        .font(.osData)
                        .foregroundStyle(selected ? Palette.ink : Palette.paper)
                        .padding(.horizontal, 8)
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

    private func toggle(_ symbol: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(on ? Palette.ink : Palette.paper.opacity(0.8))
                .frame(width: 34, height: 34)
                .background(on ? Palette.paper : .clear, in: Circle())
                .overlay(Circle().strokeBorder(on ? .clear : Palette.nightRule, lineWidth: 1))
                .frame(minWidth: 40, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
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
                Text("Sun \(Int(sun.elevation.rounded()))°").font(.osDataSmall).foregroundStyle(PortraitInk.muted)
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
                Text("Next \(store.nextShotNumber)").font(.osDataSmall).foregroundStyle(PortraitInk.muted)
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
                    .font(.osDataSmall).foregroundStyle(PortraitInk.faint)
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
                    .font(.osDataSmall).foregroundStyle(PortraitInk.faint)
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
