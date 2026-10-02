import SwiftUI

// The upright Viewfinder from the v3c Portrait board (390 × 844): project / scene and the
// clock at the top, the frame in the middle, ratio chips, time and light with a slider,
// then the shot list, shutter and zoom along the bottom.

private enum PortraitInk {
    static let muted = Palette.nightMuted
    static let soft = Color(hex: 0xB5B5AE)
    static let well = Color(hex: 0x1A1A18)
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
                HStack(spacing: 6) {
                    Text(Format.time(Date()))
                    if store.plannedMinutes != nil {
                        Text("→").foregroundStyle(PortraitInk.muted)
                        Text(Format.time(planned)).foregroundStyle(Palette.sun)
                    }
                }
                .font(.osData)
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityHint("back to now")
        }
    }
}

/// 9:16, 16:9, 1.85, 2.39 (and any custom ones), 28 high, centred. Tap the picked one
/// again to see the whole frame.
struct PortraitAspectChips: View {
    @Environment(ScoutStore.self) private var store

    private var ratios: [AspectRatio] {
        [.vertical, .hd, .flat, .scope] + store.customAspects
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips
            FadingHScroll { chips }
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(ratios) { a in
                let selected = a == store.aspect
                Button { store.setAspect(selected ? .full : a) } label: {
                    Text(a.label)
                        .font(.osData)
                        .foregroundStyle(selected ? Palette.ink : Palette.paper)
                        .padding(.horizontal, 10)
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

/// Time on the left, the light on the right, a hairline slider with an orange thumb.
struct PortraitTimeRow: View {
    @Environment(ScoutStore.self) private var store
    let sunDay: SunDay?
    let planned: Date
    let sun: SunPosition

    var body: some View {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: planned)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let light = LightPhase.from(elevation: sun.elevation, localHour: hour)

        VStack(spacing: 4) {
            HStack {
                Text(Format.time(planned)).foregroundStyle(Palette.paper)
                Spacer()
                Text(light.label).foregroundStyle(PortraitInk.soft)
            }
            .font(.osData)

            slider
        }
    }

    private var slider: some View {
        let range = hourRange
        let span = Double(range.upperBound - range.lowerBound) * 60
        return GeometryReader { geo in
            let w = geo.size.width
            let m = minutes(of: planned)
            let x = min(max(CGFloat((m - Double(range.lowerBound) * 60) / span) * w, 9), w - 9)
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.paper.opacity(0.5)).frame(height: 1)
                Circle().fill(Palette.sun).frame(width: 18, height: 18).position(x: x, y: 10)
            }
            .frame(width: w, height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    let fraction = min(max(Double(v.location.x / max(w, 1)), 0), 1)
                    store.plannedMinutes = (Double(range.lowerBound) * 60 + fraction * span).rounded()
                }
            )
            .onTapGesture(count: 2) { store.plannedMinutes = nil }
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("time of day")
        .accessibilityValue(Format.time(planned))
        .accessibilityAdjustableAction { direction in
            let m = minutes(of: planned)
            store.plannedMinutes = direction == .increment ? m + 15 : m - 15
        }
    }

    /// From an hour before sunrise to an hour after sunset, or 06–21 like the board.
    private var hourRange: ClosedRange<Int> {
        let cal = Calendar.current
        guard let rise = sunDay?.sunrise, let set = sunDay?.sunset else { return 6...21 }
        let start = max(0, cal.component(.hour, from: rise) - 1)
        let end = min(24, cal.component(.hour, from: set) + 2)
        return end - start >= 6 ? start...end : 6...21
    }

    private func minutes(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

/// Shot list box with the count, the 72pt shutter, and the lens: tap for the next focal
/// length, drag up or down to step through them.
struct PortraitBottomRow: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    let capturing: Bool
    let onShutter: () -> Void
    @State private var dragNotches = 0

    var body: some View {
        HStack {
            Spacer()
            Button { store.showingShotList = true } label: {
                Text("\(store.currentScene.shots.count)")
                    .font(.osRow)
                    .foregroundStyle(Palette.paper)
                    .frame(width: 48, height: 48)
                    .background(PortraitInk.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.nightRule, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("shot list, \(store.currentScene.shots.count) shots in this scene")
            Spacer()

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
            Spacer()

            VStack(spacing: 2) {
                Text(camera.lensLabel)
                    .font(.osRow)
                    .foregroundStyle(camera.cropIsSoft ? PortraitInk.muted : Palette.paper)
                Text("\(Format.mm(store.lensMM))mm")
                    .font(.osTiny)
                    .foregroundStyle(PortraitInk.muted)
            }
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
            .onTapGesture { stepUpWrapping() }
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        let notches = Int((-v.translation.height / 28).rounded(.towardZero))
                        if notches != dragNotches {
                            store.stepLens(notches - dragNotches)
                            dragNotches = notches
                        }
                    }
                    .onEnded { _ in dragNotches = 0 }
            )
            .sensoryFeedback(.selection, trigger: store.lensMM)
            .accessibilityElement()
            .accessibilityLabel("lens \(Format.mm(store.lensMM)) millimetres, iphone \(camera.lensLabel)")
            .accessibilityAdjustableAction { store.stepLens($0 == .increment ? 1 : -1) }
            Spacer()
        }
    }

    private func stepUpWrapping() {
        let focals = store.focalLengths
        if let last = focals.last, store.lensMM >= last {
            store.stepLens(-(focals.count - 1))
        } else {
            store.stepLens(1)
        }
    }
}
