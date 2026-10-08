import SwiftUI

// The Viewfinder chrome, laid out like the v3c prototype: Geist Mono, small type,
// thin outlined pills, paper-on-night.

private enum Ink {
    // E2: these sit straight on the live image, so the greys are paper at reduced opacity
    // (lifted from the old solid greys) and read over bright and dark scenes alike.
    /// Off and unselected labels.
    static let muted = Sheet.muted
    /// Next/previous focal lengths.
    static let faint = Palette.paper.opacity(0.38)
    /// Compass letters and hour ticks.
    static let tick = Palette.paper.opacity(0.62)
    /// Light label under the time.
    static let soft = Palette.paper.opacity(0.8)
}

// MARK: - Top bar: project / scene, + scene, compass, clock, kit

struct TopBar: View {
    @Environment(ScoutStore.self) private var store
    let heading: Double?
    let headingAccuracy: Double?
    let sunAzimuth: Double
    let planned: Date

    var body: some View {
        // Outline look, round 4: Projects on the left, "PROJECT / SCENE · FACING SOUTH-WEST"
        // in grey caps in the middle, the kit (underlined, tap to change) and the time on the right.
        ZStack {
            Text(crumb)
                .font(Fonts.mono(10))
                .tracking(0.6)
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 150)
                .accessibilityLabel(crumb.lowercased())

            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Button { store.panel = .projects } label: {
                    Text("Projects")
                        .font(Fonts.mono(11))
                        .foregroundStyle(Palette.paper)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("opens your projects")

                Spacer(minLength: 0)

                Button { store.panel = .kit } label: {
                    Text(store.kit.label.uppercased())
                        .font(Fonts.mono(10))
                        .tracking(0.6)
                        .foregroundStyle(Ink.muted)
                        .underline(color: Palette.nightRule)
                        .lineLimit(1)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 140, alignment: .trailing)
                .accessibilityLabel("kit, \(store.kit.label)")

                Text(Format.time(Date()))
                    .font(Fonts.mono(10))
                    .foregroundStyle(Ink.muted)
                    .fixedSize()
            }
        }
    }

    private var crumb: String {
        var s = "\(Self.short(store.currentProject.name, max: 18)) / \(store.currentScene.name)"
        if let heading { s += " · facing \(Bearing.facing(heading))" }
        return s.uppercased()
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
    /// The scene the "delete scene" dialog is asking about.
    @State private var deletingScene: ScoutScene?

    var body: some View {
        // HUD D: this project's scenes on top (tap to switch, + Scene to add one),
        // the overlay toggles at the bottom.
        VStack(alignment: .leading, spacing: 0) {
            Caps(text: "Scenes").foregroundStyle(Ink.muted)
                .padding(.bottom, Space.xs)
            // One quiet line per scene (name, then its count on the right), the open one
            // bright and underlined. Long lists scroll and fade at the edges, and open on the
            // current scene.
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.currentProject.scenes) { scene in
                            let current = scene.id == store.currentSceneID
                            Button { store.select(project: store.currentProjectID, scene: scene.id) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(scene.name)
                                        .font(Fonts.mono(10))
                                        .foregroundStyle(current ? Palette.paper : Ink.muted)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Spacer(minLength: 2)
                                    Text("\(scene.shots.count)")
                                        .font(.osNumTiny)
                                        .foregroundStyle(Ink.muted)
                                }
                                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(current ? [.isSelected] : [])
                            // A project always keeps at least one scene.
                            .swipeToDelete(enabled: store.currentProject.scenes.count > 1) { deletingScene = scene }
                            .id(scene.id)
                        }
                        Button { store.requestNewScene() } label: {
                            Text("+ Scene")
                                .font(Fonts.mono(10))
                                .foregroundStyle(Ink.muted)
                                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("new scene here")
                    }
                    .padding(.vertical, 6)
                }
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                           .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .onAppear { proxy.scrollTo(store.currentSceneID, anchor: .center) }
                .onChange(of: store.currentSceneID) { proxy.scrollTo(store.currentSceneID, anchor: .center) }
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
        .confirmationDialog(
            "Delete \"\(deletingScene?.name ?? "")\"?",
            isPresented: Binding(get: { deletingScene != nil }, set: { if !$0 { deletingScene = nil } }),
            titleVisibility: .visible,
            presenting: deletingScene
        ) { scene in
            Button("Delete \(scene.name)", role: .destructive) {
                store.deleteScene(scene.id)
                deletingScene = nil
            }
        } message: { scene in
            Text("Its \(ShotListView.shots(scene.shots.count)) go too, stills included. This can't be undone.")
        }
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
        // Outline look: a tick box and the word, bright when on.
        Button(action: action) {
            HStack(spacing: 7) {
                TickBox(on: on)
                Text(label)
                    .font(Fonts.mono(10))
                    .foregroundStyle(on ? Palette.paper : Ink.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 44, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Right rail: the big lens number, the lens pills, shots and the shutter

struct RightRail: View {
    @Environment(ScoutStore.self) private var store
    let capturing: Bool
    let onShutter: () -> Void

    var body: some View {
        // Outline look, round 4: the lens as one big number you drag up or down, the kit's
        // nearby focal lengths as pills under it, then Shots beside the shutter, iPhone style.
        VStack(alignment: .trailing, spacing: 10) {
            BigLens(vertical: true)
            LensPills(vertical: true)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 14) {
                ShotStack()
                Shutter(capturing: capturing, action: onShutter)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The outline shutter: a paper ring with a soft grey disc that dips when pressed.
struct Shutter: View {
    @Environment(ScoutStore.self) private var store
    let capturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(Palette.paper, lineWidth: 2).frame(width: 58, height: 58)
                Circle().fill(Color(hex: 0xC9C8C3)).frame(width: 46, height: 46)
                    .scaleEffect(capturing ? 0.88 : 1)
            }
            .frame(width: 60, height: 60)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(capturing)
        .animation(.easeOut(duration: 0.12), value: capturing)
        .accessibilityLabel("take shot \(store.nextShotNumber)")
    }
}

/// The latest still in a small rounded frame with "Shots 11" under it. Opens the shot list.
struct ShotStack: View {
    @Environment(ScoutStore.self) private var store
    /// Upright: the label sits beside the still, underlined.
    var beside = false

    var body: some View {
        let shots = store.currentProject.scenes.reduce(0) { $0 + $1.shots.count }
        let last = store.currentScene.shots.last ?? store.currentProject.scenes.flatMap(\.shots).last
        return Button { store.showingShotList = true } label: {
            let thumb = Group {
                if let last { ShotThumb(shot: last) } else { Color(hex: 0x1A1A19) }
            }
            .frame(width: beside ? 42 : 46, height: beside ? 28 : 31)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Outline.line, lineWidth: 1))

            Group {
                if beside {
                    HStack(spacing: 10) {
                        thumb
                        Text("SHOTS · \(shots)").font(Fonts.mono(10)).tracking(0.6)
                            .foregroundStyle(Palette.paper).underline(color: Palette.paper)
                    }
                } else {
                    VStack(spacing: 4) {
                        thumb
                        Text("SHOTS \(shots)").font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Palette.paper)
                    }
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(OPressRing())
        .accessibilityLabel("shot list, \(shots) shots")
    }
}

/// "24 mm" big. Drag up (or right, upright) for a longer lens, down for wider; tap for the next.
struct BigLens: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    /// Landscape drags up and down; upright, left and right.
    var vertical = true
    @State private var dragNotches = 0

    var body: some View {
        Group {
            if vertical {
                VStack(alignment: .trailing, spacing: 2) {
                    number
                    unit
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    number
                    unit
                }
            }
        }
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture { stepUpWrapping() }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { v in
                    let d = vertical ? -v.translation.height : -v.translation.width
                    let notches = Int((d / 22).rounded(.towardZero))
                    if notches != dragNotches {
                        store.stepLens(notches - dragNotches)
                        dragNotches = notches
                    }
                }
                .onEnded { _ in dragNotches = 0 }
        )
        .sensoryFeedback(.selection, trigger: store.lensMM)
        .accessibilityElement()
        .accessibilityLabel("lens \(Format.mm(store.lensMM)) millimetres")
        .accessibilityAdjustableAction { store.stepLens($0 == .increment ? 1 : -1) }
    }

    private var number: some View {
        Text(Format.mm(store.lensMM))
            .font(.osSans(vertical ? 46 : 40))
            .tracking(-1.2)
            .foregroundStyle(Palette.paper)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.2), value: store.lensMM)
    }

    private var unit: some View {
        HStack(spacing: 6) {
            // The phone's own zoom, greyed when the crop gets soft.
            Text(camera.lensLabel)
                .font(Fonts.mono(9))
                .foregroundStyle(camera.cropIsSoft ? Palette.nightRule : Ink.muted)
            Text("MM").font(Fonts.mono(12)).tracking(0.6).foregroundStyle(Ink.muted)
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

/// Five of the kit's focal lengths around the one in use, as small pills. Tap to jump.
struct LensPills: View {
    @Environment(ScoutStore.self) private var store
    var vertical = true

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 5)) : AnyLayout(HStackLayout(spacing: 6))
        layout {
            ForEach(window, id: \.self) { f in
                let on = abs(f - store.lensMM) < 0.01
                Button {
                    store.lensMM = f
                    store.save()
                } label: {
                    Text(Format.mm(f))
                        .font(Fonts.mono(10))
                        .foregroundStyle(on ? Sheet.bg : Palette.paper)
                        .frame(minWidth: 34, minHeight: 22)
                        .padding(.horizontal, 6)
                        .background(on ? Sheet.text : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Sheet.text : Outline.line, lineWidth: 1))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OPressRing())
                .accessibilityLabel("\(Format.mm(f)) millimetre lens")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: window)
    }

    private var window: [Double] {
        let focals = store.focalLengths
        guard focals.count > 5 else { return focals }
        let i = focals.firstIndex { $0 >= store.lensMM - 0.01 } ?? 0
        let start = max(0, min(focals.count - 5, i - 2))
        return Array(focals[start..<(start + 5)])
    }
}

// MARK: - Under the frame: ratio pills, the light now, and the day's line

struct BottomBar: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    let sunDay: SunDay?
    let planned: Date
    let sun: SunPosition

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: Space.s) {
                ViewThatFits(in: .horizontal) {
                    RatioPills()
                    FadingHScroll { RatioPills() }
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                LightNow(sun: sun, sunDay: sunDay, planned: planned)
            }
            SunTimeline(sunDay: sunDay, planned: planned)
        }
    }
}

/// The ratio pills and a "+" for your own. Tap the picked one again to see the whole frame.
struct RatioPills: View {
    @Environment(ScoutStore.self) private var store
    var ratios: [AspectRatio]? = nil

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ratios ?? store.aspectStrip) { a in
                OPill(label: a.label, on: a == store.aspect) {
                    store.setAspect(a == store.aspect ? .full : a)
                }
            }
            OPill(label: "+") { store.showingCustomAspect = true }
                .accessibilityLabel("more frame shapes")
        }
    }
}

/// "NOW · SIDE LIT · LEFT", orange in golden hour, with "↺ Now" once the time is moved.
struct LightNow: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    let sun: SunPosition
    let sunDay: SunDay?
    let planned: Date

    var body: some View {
        let moved = store.plannedMinutes != nil
        let golden = sunDay?.goldenWindows.contains { $0.contains(planned) } ?? false
        HStack(spacing: 10) {
            Text(((moved ? "At \(Format.time(planned))" : "Now") + " · " + read).uppercased())
                .font(Fonts.mono(10))
                .tracking(0.6)
                .foregroundStyle(golden ? Palette.sun : Palette.paper)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if moved {
                Button { store.plannedMinutes = nil } label: {
                    Text("↺ NOW").font(Fonts.mono(10)).tracking(0.6).foregroundStyle(Ink.muted)
                        .underline(color: Palette.nightRule)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("back to now")
            }
        }
    }

    private var read: String {
        guard sun.elevation > -1 else { return "Sun down" }
        guard let h = motion.heading ?? location.heading else { return "Sun \(Int(sun.elevation.rounded()))° up" }
        return LightClass.readShort(rel: LightRead.rel(sunAzimuth: sun.azimuth, heading: h))
    }
}

/// The day as one line (Elliot's round 4): sunrise and sunset ticked at the ends, golden hour
/// in orange, a fixed white NOW mark with the real time, and the orange sun you drag. Its
/// time shows above it once moved. Double-tap to go back to now.
struct SunTimeline: View {
    @Environment(ScoutStore.self) private var store
    let sunDay: SunDay?
    let planned: Date

    var body: some View {
        let (lo, hi) = range
        let span = max(hi - lo, 60)

        GeometryReader { geo in
            let w = geo.size.width
            let x = { (m: Double) in CGFloat((m - lo) / span) * w }
            let now = minutes(of: Date())
            let at = minutes(of: planned)
            let moved = store.plannedMinutes != nil

            ZStack(alignment: .topLeading) {
                Rectangle().fill(Outline.line).frame(width: w, height: 1).offset(y: 16)

                ForEach(goldenSpans, id: \.self) { g in
                    let x0 = max(0, x(g.lowerBound)), x1 = min(w, x(g.upperBound))
                    if x1 > x0 {
                        Rectangle().fill(Palette.sun.opacity(0.55)).frame(width: x1 - x0, height: 3).offset(x: x0, y: 15)
                    }
                }

                if let rise = sunDay?.sunrise, let set = sunDay?.sunset {
                    ForEach([minutes(of: rise), minutes(of: set)], id: \.self) { m in
                        Rectangle().fill(Outline.line).frame(width: 1, height: 9).offset(x: x(m), y: 12)
                        if abs(x(m) - x(now)) > 54 {
                            Text(Format.time(at: m)).font(Fonts.mono(8)).foregroundStyle(Ink.muted)
                                .fixedSize().position(x: min(max(x(m), 14), w - 14), y: 31)
                        }
                    }
                }

                // NOW: fixed, white, with the real time.
                if now >= lo && now <= hi {
                    Rectangle().fill(Palette.paper).frame(width: 1.5, height: 17).offset(x: x(now) - 0.75, y: 8)
                    Text("NOW \(Format.time(Date()))").font(Fonts.mono(8)).tracking(0.5).foregroundStyle(Palette.paper)
                        .fixedSize().position(x: min(max(x(now), 30), w - 30), y: 31)
                }

                let sx = min(max(x(at), 7), w - 7)
                Circle().fill(Palette.sun).frame(width: 14, height: 14)
                    .background(Circle().fill(Palette.sun.opacity(0.18)).frame(width: 22, height: 22))
                    .position(x: sx, y: 16)
                if moved {
                    Text(Format.time(planned)).font(Fonts.mono(9)).foregroundStyle(Palette.sun)
                        .fixedSize().position(x: min(max(sx, 18), w - 18), y: 2)
                }
            }
            .frame(width: w, height: 38, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { v in
                    let f = min(max(Double(v.location.x / max(w, 1)), 0), 1)
                    store.plannedMinutes = ((lo + f * span) / 5).rounded() * 5
                }
            )
            .onTapGesture(count: 2) { store.plannedMinutes = nil }
        }
        .frame(height: 38)
        .accessibilityElement()
        .accessibilityLabel("time of day")
        .accessibilityValue(Format.time(planned))
        .accessibilityAdjustableAction { direction in
            let m = minutes(of: planned)
            store.plannedMinutes = direction == .increment ? m + 15 : m - 15
        }
    }

    /// An hour before sunrise to an hour after sunset, in minutes; 06:00–21:00 without a sun day.
    private var range: (Double, Double) {
        guard let rise = sunDay?.sunrise, let set = sunDay?.sunset else { return (360, 1260) }
        return (max(0, minutes(of: rise) - 60), min(1440, minutes(of: set) + 60))
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
