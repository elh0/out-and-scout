import SwiftUI

// The Viewfinder chrome, laid out like the v3c prototype: Geist Mono, small type,
// thin outlined pills, paper-on-night.

private enum Ink {
    // E2: these sit straight on the live image, so the greys are paper at reduced opacity
    // (lifted from the old solid greys) and read over bright and dark scenes alike.
    /// Off and unselected labels.
    static let muted = Palette.paper.opacity(0.62)
    /// Next/previous focal lengths.
    static let faint = Palette.paper.opacity(0.38)
    /// Compass letters and hour ticks.
    static let tick = Palette.paper.opacity(0.62)
    /// Light label under the time.
    static let soft = Palette.paper.opacity(0.8)
}

/// Outlined pill on the dark viewfinder, 30 tall (hit area padded to 44).
private struct NightPill<Label: View>: View {
    var height: CGFloat = 30
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label }
                .font(.osData)
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 12)
                .frame(height: height)
                .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                .padding(.vertical, (44 - height) / 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top bar: project / scene, + scene, compass, clock, kit

struct TopBar: View {
    @Environment(ScoutStore.self) private var store
    let heading: Double?
    let headingAccuracy: Double?
    let sunAzimuth: Double
    let planned: Date

    var body: some View {
        ZStack {
            HStack(spacing: Space.xs) {
                // HUD D: "Projects" sits over the left column, the way back to all your
                // projects; the names start where the picture's window starts.
                Button { store.panel = .projects } label: {
                    Text("Projects")
                        .font(.osData)
                        .foregroundStyle(Palette.paper)
                        .underline(color: Ink.muted)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(width: 76 - Space.xs, alignment: .leading)
                .accessibilityHint("opens your projects")

                Button { store.panel = .projects } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        // Shortened in code rather than with a max-width frame: the frame
                        // always took its full 90 pt, leaving a gap before the slash.
                        Text(Self.short(store.currentProject.name)).foregroundStyle(Ink.muted)
                            .lineLimit(1)
                            .fixedSize()
                        Text("/").foregroundStyle(Ink.muted)
                        Text(store.currentScene.name).foregroundStyle(Palette.paper)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                    .font(.osData)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(store.currentProject.name), \(store.currentScene.name)")
                .accessibilityHint("opens your projects")
                // Long names truncate rather than run under the compass.
                .frame(maxWidth: 260, alignment: .leading)

                // The compass sits in the row between the two sides, so long names push it
                // over rather than running underneath it.
                Spacer(minLength: Space.xs)
                CompassTape(heading: heading, accuracy: headingAccuracy, sunAzimuth: sunAzimuth)
                    .frame(width: 150, height: 26)
                Spacer(minLength: Space.xs)

                // Just the time: white for now, orange when the sun timeline is scrubbed.
                // Tap to snap back to now.
                NightPill(action: { store.plannedMinutes = nil }) {
                    Text(Format.time(store.plannedMinutes == nil ? Date() : planned))
                        .foregroundStyle(store.plannedMinutes == nil ? Palette.paper : Palette.sun)
                }
                .lineLimit(1)
                .fixedSize()
                .accessibilityHint("back to now")

                NightPill(action: { store.panel = .kit }) {
                    Text(store.kit.label).lineLimit(1)
                }
                .frame(maxWidth: 110)
            }

        }
    }

    /// A long project name, cut to fit beside the scene.
    static func short(_ name: String, max: Int = 14) -> String {
        name.count > max ? String(name.prefix(max - 1)) + "…" : name
    }
}

/// Compass ticks centred on the camera's bearing, letters above, the sun marked in orange.
struct CompassTape: View {
    let heading: Double?
    var accuracy: Double?
    let sunAzimuth: Double
    /// Degrees shown across the width.
    private let span = 90.0

    var body: some View {
        if let heading {
            ZStack(alignment: .top) {
                Canvas { ctx, size in
                    let w = size.width
                    let mid = w / 2
                    let x = { (deg: Double) in mid + CGFloat(Bearing.difference(deg, heading) / span) * w }
                    let base: CGFloat = 24

                    let first = (Int(heading - span / 2) / 5 - 1) * 5
                    for d in stride(from: first, through: Int(heading + span / 2) + 5, by: 5) {
                        let px = x(Double(d))
                        guard px >= 0, px <= w else { continue }
                        let major = d % 45 == 0
                        let h: CGFloat = major ? 8 : (d % 15 == 0 ? 5 : 3)
                        var tick = Path()
                        tick.move(to: CGPoint(x: px, y: base))
                        tick.addLine(to: CGPoint(x: px, y: base - h))
                        ctx.stroke(tick, with: .color(Palette.paper.opacity(major ? 0.9 : 0.62)), lineWidth: 1)
                        if major {
                            let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
                            let name = names[((d / 45) % 8 + 8) % 8]
                            ctx.draw(Text(name).font(.osTiny).foregroundColor(Ink.tick), at: CGPoint(x: px, y: 5))
                        }
                    }

                    // The sun: an orange tick, pinned to the edge when it's beyond the span.
                    let sx = min(max(x(sunAzimuth), 1), w - 1)
                    var sunTick = Path()
                    sunTick.move(to: CGPoint(x: sx, y: base))
                    sunTick.addLine(to: CGPoint(x: sx, y: base - 10))
                    ctx.stroke(sunTick, with: .color(Palette.sun.opacity(0.9)), lineWidth: 1)

                    // Where the camera points.
                    ctx.fill(Path(CGRect(x: mid - 1, y: 10, width: 2, height: 16)), with: .color(Palette.sun))
                }
                .frame(height: 26)
            }
            .accessibilityElement()
            .accessibilityLabel("facing \(Format.bearing(heading))")
        } else {
            Text("Finding north…")
                .font(.osDataSmall)
                .foregroundStyle(Ink.muted)
        }
    }
}

// MARK: - Left rail: sun path, grid, level

struct LeftRail: View {
    @Environment(ScoutStore.self) private var store

    var body: some View {
        // HUD D: this project's scenes on top (tap to switch, + Scene to add one),
        // the overlay toggles at the bottom.
        VStack(alignment: .leading, spacing: 0) {
            Caps(text: "Scenes").foregroundStyle(Ink.muted)
                .padding(.bottom, Space.xs)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.currentProject.scenes) { scene in
                        let current = scene.id == store.currentSceneID
                        Button { store.select(project: store.currentProjectID, scene: scene.id) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(scene.name)
                                    .font(.osDataSmall)
                                    .foregroundStyle(current ? Palette.paper : Ink.muted)
                                    .lineLimit(1)
                                Text("\(scene.shots.count)")
                                    .font(.osNumTiny)
                                    .foregroundStyle(Ink.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(current ? [.isSelected] : [])
                    }
                    Button { store.requestNewScene() } label: {
                        Text("+ Scene")
                            .font(.osDataSmall)
                            .foregroundStyle(Palette.paper)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("new scene here")
                }
            }

            Spacer(minLength: Space.xs)
            VStack(alignment: .leading, spacing: 0) {
                RailToggle(symbol: "sun.horizon", label: "Sun Path", on: store.overlays.sunPath) { store.toggle(\.sunPath) }
                RailToggle(symbol: "grid", label: "Grid", on: store.overlays.grid) { store.toggle(\.grid) }
                RailToggle(symbol: "level", label: "Level", on: store.overlays.level) { store.toggle(\.level) }
                // Portrait layout, picked by hand rather than by tilting the phone.
                LayoutSwitch(vertical: true)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, Space.xs)
    }
}

/// A rail toggle: one word, lit and underlined when on.
struct RailToggle: View {
    let symbol: String
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        // HUD D: a word, bright and underlined when on, grey when off. No icons.
        Button(action: action) {
            Text(label)
                .font(.osData)
                .foregroundStyle(on ? Palette.paper : Ink.muted)
                .underline(on, color: Palette.paper)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 44, minHeight: 30, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Right rail: lens, shutter, shot stack

struct RightRail: View {
    @Environment(ScoutStore.self) private var store
    let capturing: Bool
    let onShutter: () -> Void

    var body: some View {
        // Lens at the top, shots at the bottom, and the shutter centred in the room between
        // them, lower down where the thumb rests (Elliot found it sat too high).
        VStack(spacing: 6) {
            // A little room above the lens wheel, so it sits nearer the thumb.
            Spacer(minLength: 0).frame(maxHeight: 18)
            LensWheel()
            Spacer(minLength: 0)
            shutter
            Spacer(minLength: 0)
            // Down in line with the bottom bar, clear of the shutter.
            ShotStack()
                .padding(.bottom, 6)
        }
        .frame(maxHeight: .infinity)
    }

    private var shutter: some View {
        VStack(spacing: 2) {
            Button(action: onShutter) {
                ZStack {
                    Circle().strokeBorder(Palette.paper, lineWidth: 3).frame(width: 64, height: 64)
                    Circle().fill(Palette.paper).frame(width: 48, height: 48)
                        .scaleEffect(capturing ? 0.85 : 1)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(capturing)
            .accessibilityLabel("pin as shot \(store.nextShotNumber)")

            (Text("Next ") + Text(store.nextShotNumber).font(.osNumSmall))
                .font(.osDataSmall)
                .foregroundStyle(Ink.muted)
        }
        .animation(.easeOut(duration: 0.12), value: capturing)
    }
}

/// Two stacked cards (the latest still on top) with the count in a paper badge.
struct ShotStack: View {
    @Environment(ScoutStore.self) private var store

    var body: some View {
        let shots = store.currentScene.shots
        return Button { store.showingShotList = true } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Ink.faint, lineWidth: 1)
                    .frame(width: 32, height: 24).offset(x: 8, y: 4)
                Group {
                    if let last = shots.last {
                        ShotThumb(shot: last)
                    } else {
                        Color(hex: 0x2B2B28)
                    }
                }
                .frame(width: 32, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.graphite, lineWidth: 1))
                .offset(x: 4, y: 10)
                Text("\(shots.count)")
                    .font(.osNumSmall)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Palette.paper, in: Capsule())
                    .offset(x: 26, y: 24)
            }
            .frame(width: 44, height: 44, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("shot list, \(shots.count) shots in this scene")
    }
}

/// Up and down step through the kit's focal lengths. Tap the big number to go up
/// (wrapping back to the widest), tap the arrows, or drag. Dragging steps once per notch
/// as you move, not just when you let go.
struct LensWheel: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    @State private var dragNotches = 0

    var body: some View {
        let focals = store.focalLengths
        let i = focals.firstIndex { $0 >= store.lensMM } ?? 0
        let next = i + 1 < focals.count ? focals[i + 1] : nil
        let prev = i > 0 ? focals[i - 1] : nil

        return VStack(spacing: 0) {
            arrow("chevron.up", delta: 1, enabled: next != nil)
            Text(next.map(Format.mm) ?? " ").font(.osNumSmall).foregroundStyle(Ink.faint)

            Button { stepUpWrapping() } label: {
                VStack(spacing: 0) {
                    Text(Format.mm(store.lensMM)).font(Fonts.mono(20)).foregroundStyle(Palette.paper)
                    // "mm" and the phone's zoom on one line, so the zoom doesn't read as the
                    // next focal length. The zoom greys out when the crop gets soft.
                    HStack(spacing: 4) {
                        Text("mm").foregroundStyle(Ink.muted)
                        Text(camera.lensLabel)
                            .font(.osNumSmall)
                            .foregroundStyle(camera.cropIsSoft ? Ink.faint : Palette.paper.opacity(0.8))
                            .padding(.horizontal, 4)
                            .overlay(Capsule().strokeBorder(Palette.nightRule, lineWidth: 1))
                    }
                    .font(.osDataSmall)
                    .padding(.bottom, 2)
                }
                .frame(width: 84)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("lens \(Format.mm(store.lensMM)) millimetres, iphone \(camera.readout)")
            .accessibilityHint("tap for the next lens")

            Text(prev.map(Format.mm) ?? " ").font(.osNumSmall).foregroundStyle(Ink.faint)
            arrow("chevron.down", delta: -1, enabled: prev != nil)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
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
        .sensoryFeedback(.selection, trigger: store.focalLengths.lastIndex { $0 <= store.lensMM + 0.01 })
    }

    private func arrow(_ icon: String, delta: Int, enabled: Bool) -> some View {
        Button { store.stepLens(delta) } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Ink.muted)
                .opacity(enabled ? 1 : 0.3)
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta > 0 ? "longer lens" : "wider lens")
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

        HStack(spacing: Space.m) {
            // All the chips when they fit; only a long custom list scrolls (with a fade).
            ViewThatFits(in: .horizontal) {
                aspectChips
                FadingHScroll { aspectChips }
            }
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            // Time at the chosen hour, the sun's height, and the light.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(Format.time(planned)).font(Fonts.mono(13)).foregroundStyle(Palette.paper)
                    (Text("Sun ") + Text("\(Int(sun.elevation.rounded()))°").font(.osNumSmall)).font(.osDataSmall).foregroundStyle(Ink.muted)
                }
                HStack(spacing: 6) {
                    LightDot(golden: light == .goldenHour, size: 6)
                    Text(light.label).font(.osData).foregroundStyle(Ink.soft).lineLimit(1)
                }
            }
            .frame(width: 112, alignment: .leading)
            .fixedSize()

            SunTimeline(sunDay: sunDay, planned: planned)
        }
    }

    private var aspectChips: some View {
        HStack(spacing: Space.xxs) {
            ForEach(store.aspectStrip) { a in
                // Tap the selected ratio again to drop the frame lines and see the full frame.
                aspectChip(a.label, selected: a == store.aspect) {
                    store.setAspect(a == store.aspect ? .full : a)
                }
            }
            Button { store.showingCustomAspect = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.paper)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Palette.nightRule, lineWidth: 1))
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("custom aspect")
        }
    }

    private func aspectChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.osData)
                .foregroundStyle(selected ? Palette.ink : Palette.paper)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(selected ? Palette.paper : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Palette.nightRule, lineWidth: 1))
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// "+2h10", "−45m", "now".
    static func offset(from now: Date, to date: Date) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded())
        if minutes == 0 { return "Now" }
        let sign = minutes > 0 ? "+" : "−"
        let m = abs(minutes)
        return m < 60 ? "\(sign)\(m)m" : "\(sign)\(m / 60)h\(String(format: "%02d", m % 60))"
    }
}

/// Drag to pick a time of day: a hairline track, golden hour as a soft orange band, an
/// orange thumb, hours underneath. Double-tap to go back to now.
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
                ForEach(goldenSpans, id: \.self) { s in
                    let x0 = max(0, x(s.lowerBound))
                    let x1 = min(w, x(s.upperBound))
                    if x1 > x0 {
                        RoundedRectangle(cornerRadius: 3).fill(Palette.sun.opacity(0.35))
                            .frame(width: x1 - x0, height: 14)
                            .offset(x: x0, y: 2)
                    }
                }

                Rectangle().fill(Palette.paper.opacity(0.5)).frame(height: 1).offset(y: 9)

                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 3)), id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(.osNumTiny)
                        .foregroundStyle(Ink.tick)
                        .fixedSize()
                        .position(x: min(max(x(Double(h) * 60), 6), w - 6), y: 28)
                }

                let mx = min(max(x(minutes(of: planned)), 8), w - 8)
                Circle().fill(Palette.sun).frame(width: 16, height: 16).position(x: mx, y: 9)
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
        // min/max: around midnight sunDay can lag a render behind, and a reversed range crashes.
        (sunDay?.goldenWindows ?? []).map {
            let a = minutes(of: $0.lowerBound), b = minutes(of: $0.upperBound)
            return min(a, b)...max(a, b)
        }
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
        // The placeholder takes the frame it's given and the photo fills it, so a tall
        // still is cropped to the box instead of spilling over neighbouring rows.
        Color(hex: 0x2B2B28)
            .overlay {
                if let image = ThumbCache.image(for: shot) {
                    Image(uiImage: image).resizable().scaledToFill()
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
        // Keep the still's own shape; frame lines crop it when it's drawn, and can change.
        let size = full.size.width > 0 ? CGSize(width: 480, height: 480 * full.size.height / full.size.width) : full.size
        let thumb = full.preparingThumbnail(of: size) ?? full
        cache.setObject(thumb, forKey: key)
        return thumb
    }

    static func full(for shot: Shot) -> UIImage? {
        guard let url = ScoutStore.photoURL(for: shot) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

/// The hand-drawn sun from the logo: half a sun on the horizon with five rays, in orange,
/// drawn with a slight wobble. A stand-in until the drawn artwork is exported as an asset.
struct SunMark: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let horizonY = h * 0.78
            let c = CGPoint(x: w / 2, y: horizonY)
            let r = w * 0.24
            var sun = Path()
            sun.move(to: CGPoint(x: c.x - r, y: horizonY))
            sun.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            sun.closeSubpath()
            ctx.fill(sun, with: .color(Palette.sun))

            var lines = Path()
            // Horizon, a touch uneven.
            lines.move(to: CGPoint(x: w * 0.04, y: horizonY + 0.4))
            lines.addQuadCurve(to: CGPoint(x: w * 0.96, y: horizonY - 0.3), control: CGPoint(x: w * 0.5, y: horizonY + 0.9))
            // Five rays, each slightly different in length.
            let lengths: [CGFloat] = [0.15, 0.19, 0.21, 0.18, 0.14]
            for (i, angle) in [200.0, 235.0, 270.0, 305.0, 340.0].enumerated() {
                let a = angle * .pi / 180
                let start = r + w * 0.07
                let end = start + w * lengths[i]
                lines.move(to: CGPoint(x: c.x + cos(a) * start, y: c.y + sin(a) * start))
                lines.addLine(to: CGPoint(x: c.x + cos(a) * end, y: c.y + sin(a) * end))
            }
            ctx.stroke(lines, with: .color(Palette.sun), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }
}
