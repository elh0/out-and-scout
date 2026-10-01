import SwiftUI

// MARK: - Top bar: project / scene, + scene, compass tape, kit chip

struct TopBar: View {
    @Environment(ScoutStore.self) private var store
    let heading: Double?
    let sunAzimuth: Double

    var body: some View {
        HStack(spacing: Space.xs) {
            Button { store.panel = .projects } label: {
                Image(systemName: "square.stack")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.nightMuted)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("switch project or scene")

            // Tap either name to rename it.
            HStack(spacing: Space.xxs) {
                EditableName(text: store.currentProject.name, font: .osRow, color: Palette.nightMuted) {
                    store.renameProject(store.currentProjectID, to: $0)
                }
                Text("/").font(.osRow).foregroundStyle(Palette.nightMuted)
                EditableName(text: store.currentScene.name, font: .osRow, color: Palette.paper) {
                    store.renameScene(store.currentSceneID, to: $0)
                }
            }
            .frame(height: 44)

            Chip(label: "+ scene", mono: false) { store.requestNewScene() }

            Spacer(minLength: Space.xs)
            CompassTape(heading: heading, sunAzimuth: sunAzimuth)
                .frame(width: 168, height: 30)
            Spacer(minLength: Space.xs)

            Chip(label: store.kit.label) { store.panel = .kit }
                .lineLimit(1)
        }
    }
}

/// A strip of compass ticks centred on the camera's bearing, with the sun marked.
struct CompassTape: View {
    let heading: Double?
    let sunAzimuth: Double
    /// Degrees shown across the width.
    private let span = 90.0

    var body: some View {
        if let heading {
            Canvas { ctx, size in
                let w = size.width
                let mid = w / 2
                let x = { (deg: Double) in mid + CGFloat(Bearing.difference(deg, heading) / span) * w }

                let first = (Int(heading - span / 2) / 5 - 1) * 5
                for d in stride(from: first, through: Int(heading + span / 2) + 5, by: 5) {
                    let px = x(Double(d))
                    guard px >= 0, px <= w else { continue }
                    let major = d % 45 == 0
                    var tick = Path()
                    tick.move(to: CGPoint(x: px, y: size.height))
                    tick.addLine(to: CGPoint(x: px, y: size.height - (major ? 8 : 4)))
                    ctx.stroke(tick, with: .color(Palette.paper.opacity(major ? 0.8 : 0.35)), lineWidth: 1)
                    if major {
                        let names = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
                        let name = names[((d / 45) % 8 + 8) % 8]
                        ctx.draw(Text(name).font(.osDataSmall).foregroundColor(Palette.nightMuted), at: CGPoint(x: px, y: 6))
                    }
                }

                // Sun: on the tape if it's within the span, otherwise pinned to the edge it's beyond.
                let sx = min(max(x(sunAzimuth), 4), w - 4)
                let inView = abs(Bearing.difference(sunAzimuth, heading)) <= span / 2
                let dot = Path(ellipseIn: CGRect(x: sx - 4, y: size.height - 16, width: 8, height: 8))
                if inView {
                    ctx.fill(dot, with: .color(Palette.sun))
                } else {
                    ctx.stroke(dot, with: .color(Palette.sun), lineWidth: 1.5)
                }

                var caret = Path()
                caret.move(to: CGPoint(x: mid, y: size.height - 10))
                caret.addLine(to: CGPoint(x: mid, y: size.height))
                ctx.stroke(caret, with: .color(Palette.paper), lineWidth: 2)
            }
            .accessibilityLabel("facing \(Format.bearing(heading))")
        } else {
            Text("finding north…")
                .font(.osDataSmall)
                .foregroundStyle(Palette.nightMuted)
        }
    }
}

// MARK: - Left rail: sun path, grid, level

struct LeftRail: View {
    @Environment(ScoutStore.self) private var store

    var body: some View {
        VStack(spacing: Space.m) {
            RailToggle(symbol: "sun.horizon", label: "sun path", on: store.overlays.sunPath) { store.toggle(\.sunPath) }
            RailToggle(symbol: "grid", label: "grid", on: store.overlays.grid) { store.toggle(\.grid) }
            RailToggle(symbol: "level", label: "level", on: store.overlays.level) { store.toggle(\.level) }
        }
        .frame(maxHeight: .infinity)
    }
}

struct RailToggle: View {
    let symbol: String
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 36, height: 28)
                Text(label)
                    .font(.osDataSmall)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(on ? Palette.paper : Palette.nightMuted.opacity(0.7))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Right rail: lens wheel, shutter, shot stack

struct RightRail: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    let capturing: Bool
    let onShutter: () -> Void

    var body: some View {
        VStack(spacing: Space.xs) {
            lensWheel
            Spacer(minLength: 0)
            shutter
            Spacer(minLength: 0)
            shotStack
        }
        .frame(maxHeight: .infinity)
    }

    private var lensWheel: some View {
        let focals = store.focalLengths
        let i = focals.firstIndex { $0 >= store.lensMM } ?? 0
        let next = i + 1 < focals.count ? focals[i + 1] : nil
        let prev = i > 0 ? focals[i - 1] : nil

        return VStack(spacing: 0) {
            Button { store.stepLens(1) } label: {
                Text(next.map(Format.mm) ?? " ").font(.osData).foregroundStyle(Palette.nightMuted)
                    .frame(width: 60, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(next == nil)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(Format.mm(store.lensMM)).font(Fonts.sans(28, .medium))
                Text("mm").font(.osDataSmall)
            }
            .foregroundStyle(Palette.paper)

            Text(camera.readout)
                .font(.osDataSmall)
                .foregroundStyle(camera.cropIsSoft ? Palette.nightMuted.opacity(0.5) : Palette.nightMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 24)
                .accessibilityLabel("which iphone lens is live: \(camera.readout)")

            Button { store.stepLens(-1) } label: {
                Text(prev.map(Format.mm) ?? " ").font(.osData).foregroundStyle(Palette.nightMuted)
                    .frame(width: 60, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(prev == nil)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { v in
                store.stepLens(v.translation.height < 0 ? 1 : -1)
            }
        )
    }

    private var shutter: some View {
        VStack(spacing: 2) {
            Button(action: onShutter) {
                ZStack {
                    Circle().strokeBorder(Palette.paper, lineWidth: 3).frame(width: 64, height: 64)
                    Circle().fill(Palette.paper).frame(width: 50, height: 50)
                        .scaleEffect(capturing ? 0.85 : 1)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(capturing)
            .accessibilityLabel("pin as shot \(store.nextShotNumber)")

            Text("next \(store.nextShotNumber)")
                .font(.osDataSmall)
                .foregroundStyle(Palette.nightMuted)
        }
        .animation(.easeOut(duration: 0.12), value: capturing)
    }

    private var shotStack: some View {
        let shots = store.currentScene.shots
        return Button { store.showingShotList = true } label: {
            HStack(spacing: Space.xs) {
                if let last = shots.last {
                    ShotThumb(shot: last).frame(width: 40, height: 40)
                } else {
                    RoundedRectangle(cornerRadius: Radius.readout)
                        .strokeBorder(Palette.nightRule, lineWidth: 1)
                        .frame(width: 40, height: 40)
                }
                Text("\(shots.count)")
                    .font(.osData)
                    .foregroundStyle(Palette.paper)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("shot list, \(shots.count) shots in this scene")
    }

}

// MARK: - Bottom bar: aspect strip, time + light, sun timeline

struct BottomBar: View {
    @Environment(ScoutStore.self) private var store
    let sunDay: SunDay?
    let planned: Date
    let sun: SunPosition

    var body: some View {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: planned)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        let light = LightPhase.from(elevation: sun.elevation, localHour: hour)

        HStack(spacing: Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.xxs) {
                    ForEach(store.aspectStrip) { a in
                        Chip(label: a.label, selected: a == store.aspect) { store.setAspect(a) }
                    }
                    Chip(label: "+") { store.showingCustomAspect = true }
                        .accessibilityLabel("custom aspect")
                }
            }
            .frame(maxWidth: 250)
            .fixedSize(horizontal: false, vertical: true)

            Button { store.plannedMinutes = nil } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Format.time(planned))
                        .font(.osData)
                        .foregroundStyle(store.plannedMinutes == nil ? Palette.sun : Palette.paper)
                    Text(light.label)
                        .font(.osDataSmall)
                        .foregroundStyle(Palette.nightMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(minWidth: 70, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("back to now")

            SunTimeline(sunDay: sunDay, planned: planned)
        }
    }
}

/// Drag to pick a time of day. Golden-hour windows are the sun colour at 30%.
/// Double-tap to go back to now.
struct SunTimeline: View {
    @Environment(ScoutStore.self) private var store
    let sunDay: SunDay?
    let planned: Date

    var body: some View {
        let range = hourRange
        let span = Double(range.upperBound - range.lowerBound) * 60

        GeometryReader { geo in
            let w = geo.size.width
            let x = { (minutes: Double) in CGFloat((minutes - Double(range.lowerBound) * 60) / span) * w }

            ZStack(alignment: .topLeading) {
                Rectangle().fill(Palette.nightRule).frame(height: 1).offset(y: 14)

                ForEach(goldenSpans, id: \.self) { s in
                    let x0 = max(0, x(s.lowerBound))
                    let x1 = min(w, x(s.upperBound))
                    if x1 > x0 {
                        Rectangle().fill(Palette.sun.opacity(0.3))
                            .frame(width: x1 - x0, height: 8)
                            .offset(x: x0, y: 10)
                    }
                }

                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 3)), id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(Fonts.mono(9))
                        .foregroundStyle(Palette.nightMuted)
                        .fixedSize()
                        .position(x: x(Double(h) * 60), y: 30)
                }

                let mx = min(max(x(minutes(of: planned)), 0), w)
                Rectangle().fill(Palette.sun).frame(width: 1, height: 18).offset(x: mx, y: 5)
                Circle().fill(Palette.sun).frame(width: 10, height: 10).position(x: mx, y: 14)
            }
            .frame(width: w, height: 44, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    let fraction = min(max(Double(v.location.x / max(w, 1)), 0), 1)
                    store.plannedMinutes = (Double(range.lowerBound) * 60 + fraction * span).rounded()
                }
            )
            .onTapGesture(count: 2) { store.plannedMinutes = nil }
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel("time of day")
        .accessibilityValue(Format.time(planned))
        .accessibilityAdjustableAction { direction in
            let m = minutes(of: planned)
            store.plannedMinutes = direction == .increment ? m + 15 : m - 15
        }
    }

    /// Hours shown: from an hour before sunrise to an hour after sunset, or 06–21.
    private var hourRange: ClosedRange<Int> {
        let cal = Calendar.current
        guard let rise = sunDay?.sunrise, let set = sunDay?.sunset else { return 6...21 }
        let start = max(0, cal.component(.hour, from: rise) - 1)
        let end = min(24, cal.component(.hour, from: set) + 2)
        return end - start >= 6 ? start...end : 6...21
    }

    private var goldenSpans: [ClosedRange<Double>] {
        (sunDay?.goldenWindows ?? []).map { minutes(of: $0.lowerBound)...minutes(of: $0.upperBound) }
    }

    private func minutes(of date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        // The end of a window can land on the next midnight.
        return m == 0 && date > Calendar.current.startOfDay(for: planned) ? 1440 : m
    }
}

/// A shot's still, cropped to its frame, radius 6.
struct ShotThumb: View {
    let shot: Shot

    var body: some View {
        Group {
            if let image = ThumbCache.image(for: shot) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(hex: 0x2B2B28)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.readout, style: .continuous))
    }
}

enum ThumbCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for shot: Shot) -> UIImage? {
        guard let url = ScoutStore.photoURL(for: shot) else { return nil }
        let key = url.lastPathComponent as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let full = UIImage(contentsOfFile: url.path) else { return nil }
        let thumb = full.preparingThumbnail(of: CGSize(width: 480, height: 480 / max(shot.aspect.value, 0.3))) ?? full
        cache.setObject(thumb, forKey: key)
        return thumb
    }

    static func full(for shot: Shot) -> UIImage? {
        guard let url = ScoutStore.photoURL(for: shot) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
