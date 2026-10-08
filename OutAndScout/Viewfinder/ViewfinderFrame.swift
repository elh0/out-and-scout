import SwiftUI
import Vision
import ImageIO

/// The live image with frame lines for the chosen aspect, the sun path, grid, level, HUD,
/// and tap-to-focus / long-press AE/AF lock with the sun (exposure) slider.
struct ViewfinderFrame: View {
    @Environment(ScoutStore.self) private var store
    @Environment(CameraController.self) private var camera
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion

    let sun: SunPosition
    let sunDay: SunDay?
    let planned: Date
    @Binding var frameFraction: Double
    /// Upright phone: the v3c portrait frame (342 wide on a 390 screen).
    var portrait = false
    /// E2: the image fills the whole screen under floating controls. Lines only show for a
    /// picked ratio, and the label hides when the frame is big enough to reach the controls.
    var fullBleed = false
    /// Full bleed: the space the controls take at each edge. The frame no longer shrinks to
    /// fit inside it (that made wide lenses look tight); notices sit inside it.
    var clear = EdgeInsets()


    /// The light chip in the frame's bottom-left corner: "Side lit, sun on the left".
    private var chipText: String {
        if sun.elevation <= -1 { return "Sun down · \(moon.phaseName.lowercased())" }
        guard let heading = motion.heading ?? location.heading else { return "Sun \(Int(sun.elevation.rounded()))° up" }
        return LightClass.readLong(rel: LightRead.rel(sunAzimuth: sun.azimuth, heading: heading))
    }

    /// The moon at the planned time, for after sunset.
    private var moon: MoonInfo {
        MoonCalculator.info(at: planned, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    @State private var focusPoint: CGPoint?
    @State private var focusShownAt = Date.distantPast
    /// The lens when the pinch began.
    @State private var pinchStartMM: Double?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // The viewfinder fills the space between the rails. The chosen ratio's lines are
            // made as big as they'll go (with a small margin so they read as a frame), and the
            // phone zooms so the lines show exactly what the cine lens would. Everything outside
            // is dimmed, like the v3c prototype. "full" is the whole sensor mode.
            let frame = frameRect(size)
            // A lens wider than the phone: the frame lines stay at their true size and the
            // picture shrinks inside them, leaving a grey margin the iPhone can't see.
            let shrink = camera.status == .running ? camera.shrink : 1
            let anchor = UnitPoint(x: frame.midX / max(size.width, 1), y: frame.midY / max(size.height, 1))
            let img = imageRect(size)

            ZStack(alignment: .topLeading) {
                if shrink > 1 {
                    Sheet.bg
                    Color(hex: 0x262624)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                cameraLayer
                    // Only the picture shrinks, not Fit's dark bars around it.
                    .mask(alignment: .topLeading) {
                        Rectangle().frame(width: img.width, height: img.height).offset(x: img.minX, y: img.minY)
                    }
                    .scaleEffect(1 / shrink, anchor: anchor)

                // Corner ticks always mark the frame, Full included, and outside it goes dark
                // enough that there's no doubt what's in shot.
                // HUD D (Elliot, 6 Oct 2026): only the shot shows. Outside the frame is solid
                // ink, so nothing bleeds in around the edges.
                AspectMask(frame: frame, shade: fullBleed ? 0.55 : nil,
                           ticks: fullBleed, solid: fullBleed ? nil : Sheet.bg)

                if store.overlays.grid {
                    ThirdsGrid().frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                }
                if store.overlays.level {
                    LevelLine(roll: motion.roll).frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                }
                if store.overlays.sunPath, let heading = (motion.heading ?? location.heading) {
                    SunPathOverlay(
                        sunDay: sunDay,
                        sun: sun,
                        // When the time is scrubbed, a ring marks where the sun is right now.
                        nowSun: store.plannedMinutes == nil ? nil : SunCalculator.position(
                            at: Date(), latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                        // After sunset, the moon takes the sun's place.
                        moon: sun.elevation < -1 ? moon : nil,
                        projector: Projector(heading: heading, elevation: motion.cameraElevation, hfov: 2 * atan(tan(camera.previewHFOV * .pi / 360) * shrink) * 360 / .pi, size: size)
                    )
                }

                // Outline look: the frame is a white window, and the light as it falls on this
                // shot sits in its bottom-left corner as a small chip.
                if !fullBleed {
                    Rectangle()
                        .strokeBorder(Palette.paper, lineWidth: 2)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .allowsHitTesting(false)
                }
                Text(chipText.uppercased())
                    .font(Fonts.mono(9))
                    .tracking(0.6)
                    .foregroundStyle(Palette.paper)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Sheet.bg.opacity(0.82), in: Capsule())
                    .overlay(Capsule().strokeBorder(Outline.line, lineWidth: 1))
                    .fixedSize()
                    .offset(x: frame.minX + 8, y: frame.maxY - 30)
                    .allowsHitTesting(false)

                // Honest about the phone's limit: say how wide it can really go here.
                if camera.isTooWide, camera.status == .running {
                    Text("Grey edge: outside what the iPhone sees · it reaches ≈ \(widestFocal(size: size, frame: frame))mm")
                        .font(.osDataSmall)
                        .foregroundStyle(Palette.paper)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.hud, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        // E2: centred in the open space under the top controls, so it never
                        // sits on the compass or the scene buttons.
                        .frame(width: fullBleed ? max(size.width - clear.leading - clear.trailing, 1) : frame.width)
                        // Upright, the sun's height sits top-right, so this goes near the bottom.
                        .offset(x: fullBleed ? clear.leading : frame.minX,
                                y: fullBleed ? clear.top + Space.xs : portrait ? frame.maxY - 44 : frame.minY + Space.xs)
                }

                if let p = focusPoint {
                    FocusSquare(locked: camera.aeAfLocked, bias: camera.exposureBias) { camera.setExposureBias($0) }
                        .position(p)
                        .id(focusShownAt)
                        .task(id: focusShownAt) {
                            // The exposure offset now carries over between taps, so hide the
                            // square unless it was locked or the offset was changed this time.
                            let biasAtTap = camera.exposureBias
                            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                            if !camera.aeAfLocked && camera.exposureBias == biasAtTap { focusPoint = nil }
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                camera.focus(atLayerPoint: layerPoint(p, size: size, frame: frame))
                showFocus(at: p)
            }
            // Pinch like the Camera app: smooth while your fingers move (out for longer, in for
            // wider), then it settles on the nearest lens in the kit when you let go.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        let start = pinchStartMM ?? store.lensMM
                        pinchStartMM = start
                        let focals = store.focalLengths
                        guard let lo = focals.first, let hi = focals.last else { return }
                        store.lensMM = min(max((start * Double(v.magnification)).rounded(), lo), hi)
                    }
                    .onEnded { _ in
                        pinchStartMM = nil
                        let mm = store.lensMM
                        if let nearest = store.focalLengths.min(by: { abs(log($0 / mm)) < abs(log($1 / mm)) }) {
                            store.lensMM = nearest
                        }
                        store.save()
                    }
            )
            .onLongPressGesture(minimumDuration: 0.6) {
                // SwiftUI's long press doesn't report a location; lock where the last tap was, or the centre.
                let p = focusPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)
                camera.lock(atLayerPoint: layerPoint(p, size: size, frame: frame))
                showFocus(at: p)
            }
            .onAppear { syncLens(size: size, frame: frame) }
            .onChange(of: LensKey(lens: store.lensMM, kit: store.kit, aspect: store.aspect, size: size, portrait: portrait)) {
                syncLens(size: size, frame: frame)
            }
            .onChange(of: camera.status) { syncLens(size: size, frame: frame) }
        }
    }

    @ViewBuilder private var cameraLayer: some View {
        switch camera.status {
        case .running:
            CameraPreview(camera: camera)
        case .unauthorized:
            placeholder("Camera access is off. Turn it on in Settings to frame shots.", settingsButton: true)
        case .unavailable:
            placeholder("No camera here. Pins still work, without a still.", settingsButton: false)
        case .idle:
            Palette.night
        }
    }

    private func placeholder(_ text: String, settingsButton: Bool) -> some View {
        VStack(spacing: Space.s) {
            Text(text)
                .font(.osSupport)
                .foregroundStyle(Palette.nightMuted)
                .multilineTextAlignment(.center)
            if settingsButton, let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .buttonStyle(PillButtonStyle(kind: .secondary, onDark: true))
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x1A1A18))
    }


    private func showFocus(at p: CGPoint) {
        focusPoint = p
        focusShownAt = Date()
    }

    /// Upright with a tall ratio (or "full"), the cine camera is turned on its side too.
    static func sensorOnSide(aspect: AspectRatio, portrait: Bool) -> Bool {
        portrait && (aspect.isFull || aspect.value < 1)
    }

    /// The shape of the sensor frame as it sits on screen.
    static func sensorAspect(kit: Kit, aspect: AspectRatio, portrait: Bool) -> Double {
        sensorOnSide(aspect: aspect, portrait: portrait) ? 1 / kit.frameAspect : kit.frameAspect
    }

    private var onSide: Bool { Self.sensorOnSide(aspect: store.aspect, portrait: portrait) }
    private var sensorAspect: Double { Self.sensorAspect(kit: store.kit, aspect: store.aspect, portrait: portrait) }

    /// The ratio the lines are drawn at; "full" is the sensor mode's own shape.
    private var lineAspect: Double {
        store.aspect.isFull ? sensorAspect : store.aspect.value
    }

    /// Where the cine frame sits. Its width decides how wide a lens the phone can show, so
    /// it's kept as big as it will go.
    private func frameRect(_ size: CGSize) -> CGRect {
        // The picture always fills the screen (no bars, no modes); every ratio, Full included,
        // is fitted whole inside it with corner ticks, so what's in the lines is the shot.
        let box = inset(size)
        return FrameMath.fit(aspect: lineAspect, in: box.size).offsetBy(dx: box.minX, dy: box.minY)
    }

    /// A tap on screen to the same spot on the preview layer, undoing the wide-lens shrink.
    private func layerPoint(_ p: CGPoint, size: CGSize, frame: CGRect) -> CGPoint {
        let s = camera.status == .running ? camera.shrink : 1
        return CGPoint(x: frame.midX + (p.x - frame.midX) * s, y: frame.midY + (p.y - frame.midY) * s)
    }

    /// Where the camera picture sits: always the whole view, edge to edge.
    private func imageRect(_ size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size)
    }

    /// A small margin so even the widest ratio reads as a frame rather than full bleed.
    /// Portrait follows the board: 24 each side, 5 top and bottom. E2 keeps the same margin
    /// (fitting the lines between the controls made every lens look too tight) and marks
    /// the frame with corner ticks, so no line runs through the controls.
    /// HUD D (landscape and upright) has its own window, so the frame fills it exactly:
    /// no margin of picture around the shot.
    private func inset(_ size: CGSize) -> CGRect {
        guard fullBleed else { return CGRect(origin: .zero, size: size) }
        return CGRect(origin: .zero, size: size).insetBy(dx: portrait ? 24 : 10, dy: portrait ? 5 : 8)
    }

    /// How much of the sensor's width the lines take: 1 for ratios wider than the sensor
    /// (extracted across the full width), less for taller ones.
    private var linesToSensorWidth: Double {
        lineAspect >= sensorAspect ? 1 : lineAspect / sensorAspect
    }

    /// The cine lens's view across the sensor as it sits on screen.
    private var sensorWidthFOV: Double {
        let h = store.kit.horizontalFOV(focal: store.lensMM)
        guard onSide else { return h }
        return 2 * atan(tan(h * .pi / 360) / store.kit.frameAspect) * 180 / .pi
    }

    private func syncLens(size: CGSize, frame: CGRect) {
        guard size.width > 0, frame.width > 0 else { return }
        camera.portrait = portrait
        let r = linesToSensorWidth
        let sensorHFOV = sensorWidthFOV
        // The lines see r of the sensor's width.
        let linesHFOV = 2 * atan(r * tan(sensorHFOV * .pi / 360)) * 180 / .pi
        // Measured against the picture, which in Fit is narrower than the screen.
        let fraction = Double(frame.width / imageRect(size).width)
        camera.match(targetHFOV: linesHFOV, frameFraction: fraction)
        // The still keeps the whole sensor frame, which is 1/r times as wide as the lines.
        frameFraction = min(fraction / r, 1)
    }

    /// The widest cine focal length the phone can show truthfully in these frame lines.
    private func widestFocal(size: CGSize, frame: CGRect) -> String {
        guard size.width > 0 else { return "—" }
        let linesMax = camera.widestHFOV(frameFraction: Double(frame.width / imageRect(size).width))
        let sensorHalf = tan(linesMax * .pi / 360) / linesToSensorWidth
        let width = store.kit.mode.widthMM * store.kit.lenses.squeeze / (onSide ? store.kit.frameAspect : 1)
        return Format.mm((width / (2 * sensorHalf)).rounded())
    }

    private struct LensKey: Equatable {
        var lens: Double
        var kit: Kit
        var aspect: AspectRatio
        var size: CGSize
        var portrait: Bool
    }
}

enum FrameMath {
    /// Largest rect of `aspect` centred in `size`.
    static func fit(aspect: Double, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        var w = size.width
        var h = w / aspect
        if h > size.height {
            h = size.height
            w = h * aspect
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

/// Darkens everything outside the frame lines (ink at 72%) and draws a thin frame line.
struct AspectMask: View {
    let frame: CGRect
    /// Draw the frame lines (E2 leaves them off until a ratio is picked).
    var lines = true
    /// How dark outside the frame goes; nil is the usual HUD shade.
    var shade: Double? = nil
    /// E2: corner ticks instead of a full outline, so the frame never cuts through a control.
    var ticks = false
    /// HUD D: outside the frame is this colour, fully opaque, with a quiet outline.
    var solid: Color? = nil

    var body: some View {
        Canvas { ctx, size in
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addRect(frame)
            let fill = solid ?? shade.map { Color.black.opacity($0) } ?? Palette.hud
            ctx.fill(outside, with: .color(fill), style: FillStyle(eoFill: true))
            if lines {
                let r = frame.insetBy(dx: 0.5, dy: 0.5)
                let color = GraphicsContext.Shading.color(Palette.paper.opacity(solid != nil ? 0.6 : shade != nil ? 0.7 : 0.85))
                if ticks {
                    let t: CGFloat = 14
                    var p = Path()
                    for (x, y, dx, dy) in [(r.minX, r.minY, t, t), (r.maxX, r.minY, -t, t),
                                           (r.minX, r.maxY, t, -t), (r.maxX, r.maxY, -t, -t)] {
                        p.move(to: CGPoint(x: x + dx, y: y))
                        p.addLine(to: CGPoint(x: x, y: y))
                        p.addLine(to: CGPoint(x: x, y: y + dy))
                    }
                    ctx.stroke(p, with: color, lineWidth: 1)
                } else {
                    ctx.stroke(Path(r), with: color, lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct ThirdsGrid: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            for i in 1...2 {
                let x = size.width * CGFloat(i) / 3
                let y = size.height * CGFloat(i) / 3
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(p, with: .color(Palette.paper.opacity(0.35)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

/// A horizon line that tilts with the phone. Solid when within half a degree of level.
struct LevelLine: View {
    let roll: Double

    var body: some View {
        let level = abs(roll) < 0.5
        ZStack {
            Rectangle()
                .fill(Palette.paper.opacity(level ? 0.9 : 0.5))
                .frame(width: 160, height: 1)
                .rotationEffect(.degrees(level ? 0 : -roll))
            Rectangle()
                .fill(Palette.paper.opacity(0.35))
                .frame(width: 40, height: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

/// Focus square with the sun slider beside it for exposure.
struct FocusSquare: View {
    let locked: Bool
    let bias: Float
    let setBias: (Float) -> Void

    @State private var dragStart: Float?

    var body: some View {
        HStack(alignment: .center, spacing: Space.xs) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Palette.paper, lineWidth: 1)
                .frame(width: 72, height: 72)
                .overlay(alignment: .top) {
                    if locked {
                        Text("AE/AF Lock")
                            .font(.osDataSmall)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 4)
                            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 3))
                            .offset(y: -18)
                            .fixedSize()
                    }
                }

            // Drag up/down on the sun to brighten/darken, ±2 stops.
            ZStack {
                Rectangle().fill(Palette.paper.opacity(0.5)).frame(width: 1, height: 96)
                Circle()
                    .fill(Palette.sun)
                    .frame(width: 16, height: 16)
                    .offset(y: CGFloat(-bias) * 24)
            }
            .frame(width: 44, height: 112)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let start = dragStart ?? bias
                        if dragStart == nil { dragStart = bias }
                        setBias(min(max(start - Float(v.translation.height / 24), -2), 2))
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .offset(x: 26) // keep the square itself centred on the tap
    }
}

/// Projects a sun position (azimuth, elevation) into the viewfinder.
/// Rectilinear projection; ignores roll, which is fine for a phone held roughly level.
struct Projector {
    var heading: Double
    var elevation: Double
    var hfov: Double
    var size: CGSize

    func point(azimuth: Double, elevation el: Double) -> CGPoint? {
        let rad = { (d: Double) in d * .pi / 180 }
        let dx = Bearing.difference(azimuth, heading)
        let dy = el - elevation
        guard abs(dx) < 85, abs(dy) < 85 else { return nil }
        let halfW = tan(rad(hfov / 2))
        let halfH = halfW * Double(size.height / max(size.width, 1))
        let x = Double(size.width) / 2 * (1 + tan(rad(dx)) / halfW)
        let y = Double(size.height) / 2 * (1 - tan(rad(dy)) / halfH)
        return CGPoint(x: x, y: y)
    }
}

/// The day's sun path: a solid line, golden-hour stretches in orange, a dot and label on
/// each hour, the sun at the chosen time (filled) with its azimuth and elevation, and a ring
/// for where it is now when the time is scrubbed. Off-screen, an edge marker says which way.
struct SunPathOverlay: View {
    let sunDay: SunDay?
    let sun: SunPosition
    var nowSun: SunPosition?
    /// Set once the sun is down: drawn instead of the sun, with its phase.
    var moon: MoonInfo?
    let projector: Projector

    var body: some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            if let day = sunDay {
                var arc = Path()
                var golden = Path()
                var started = false
                var goldenStarted = false
                var hours: [(CGPoint, Int)] = []
                let calendar = Calendar.current
                for s in day.samples where s.position.elevation > -8 {
                    guard let p = projector.point(azimuth: s.position.azimuth, elevation: s.position.elevation) else {
                        started = false; goldenStarted = false; continue
                    }
                    if started { arc.addLine(to: p) } else { arc.move(to: p); started = true }
                    let isGolden = s.position.elevation >= -4 && s.position.elevation < 6
                    if isGolden {
                        if goldenStarted { golden.addLine(to: p) } else { golden.move(to: p); goldenStarted = true }
                    } else {
                        goldenStarted = false
                    }
                    let c = calendar.dateComponents([.hour, .minute], from: s.time)
                    if c.minute == 0, s.position.elevation > -4, bounds.contains(p) { hours.append((p, c.hour ?? 0)) }
                }
                ctx.stroke(arc, with: .color(Palette.paper.opacity(0.55)), lineWidth: 1)
                ctx.stroke(golden, with: .color(Palette.sun.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                for (p, h) in hours {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(Palette.paper.opacity(0.8)))
                    let label = Text(String(format: "%02d", h)).font(Fonts.mono(9)).foregroundColor(Palette.paper.opacity(0.7))
                    ctx.draw(label, at: CGPoint(x: p.x, y: p.y + 9), anchor: .top)
                }

                // Horizon
                if let l = projector.point(azimuth: projector.heading - 80, elevation: 0),
                   let r = projector.point(azimuth: projector.heading + 80, elevation: 0) {
                    var h = Path()
                    h.move(to: CGPoint(x: 0, y: l.y)); h.addLine(to: CGPoint(x: size.width, y: r.y))
                    ctx.stroke(h, with: .color(Palette.paper.opacity(0.2)), lineWidth: 0.5)
                }
            }

            let sunPoint = projector.point(azimuth: sun.azimuth, elevation: sun.elevation)
            if let now = nowSun, let p = projector.point(azimuth: now.azimuth, elevation: now.elevation), bounds.contains(p) {
                let r: CGFloat = 7
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Palette.sun), lineWidth: 1.5)
                // Only label it when it's clear of the planned sun and its readout.
                let clear = sunPoint.map { hypot($0.x - p.x, $0.y - p.y) > 60 } ?? true
                if clear, p.y > 24 {
                    ctx.draw(Text("Now").font(.osDataSmall).foregroundColor(Palette.paper), at: CGPoint(x: p.x, y: p.y - r - 3), anchor: .bottom)
                }
            }

            if let moon {
                drawMoon(moon, in: &ctx, size: size)
            } else if let p = projector.point(azimuth: sun.azimuth, elevation: sun.elevation),
               bounds.insetBy(dx: -8, dy: -8).contains(p) {
                let r: CGFloat = 7
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(Palette.sun))
                let readout = ctx.resolve(Text("Az \(Int(sun.azimuth.rounded()))° · El \(Int(sun.elevation.rounded()))°")
                    .font(.osNumSmall).foregroundColor(Palette.paper))
                // Keep the readout inside the frame: flip sides near the right edge and hold it
                // clear of the top and bottom.
                let w = readout.measure(in: size).width
                let right = p.x + r + 5 + w < size.width - 6
                let y = min(max(p.y, 12), size.height - 12)
                ctx.draw(readout, at: CGPoint(x: right ? p.x + r + 5 : max(p.x - r - 5, w + 6), y: y), anchor: right ? .leading : .trailing)
            } else {
                // Off-screen: arrow at the edge pointing the way to turn.
                let left = Bearing.difference(sun.azimuth, projector.heading) < 0
                let y = size.height / 2
                let x: CGFloat = left ? 14 : size.width - 14
                var tri = Path()
                if left {
                    tri.move(to: CGPoint(x: x - 6, y: y)); tri.addLine(to: CGPoint(x: x + 4, y: y - 6)); tri.addLine(to: CGPoint(x: x + 4, y: y + 6))
                } else {
                    tri.move(to: CGPoint(x: x + 6, y: y)); tri.addLine(to: CGPoint(x: x - 4, y: y - 6)); tri.addLine(to: CGPoint(x: x - 4, y: y + 6))
                }
                tri.closeSubpath()
                ctx.fill(tri, with: .color(Palette.sun))
                let label = Text("Sun \(Int(sun.azimuth.rounded()))°").font(.osDataSmall).foregroundColor(Palette.paper)
                ctx.draw(label, at: CGPoint(x: left ? x + 10 : x - 10, y: y + 16), anchor: left ? .leading : .trailing)
            }
        }
        .allowsHitTesting(false)
    }

    /// The moon where it is, lit to its phase, with "Moon · Waxing gibbous · 78% lit"; an arrow
    /// at the edge when it's out of frame; a quiet line when it hasn't risen.
    private func drawMoon(_ moon: MoonInfo, in ctx: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        let label = "Moon · \(moon.summary)"
        guard moon.position.elevation > -0.5 else {
            ctx.draw(Text("Moon below the horizon · \(moon.summary)").font(.osDataSmall).foregroundColor(Palette.paper.opacity(0.8)),
                     at: CGPoint(x: size.width / 2, y: 14), anchor: .top)
            return
        }
        if let p = projector.point(azimuth: moon.position.azimuth, elevation: moon.position.elevation),
           bounds.insetBy(dx: -8, dy: -8).contains(p) {
            let r: CGFloat = 8
            let disc = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: disc), with: .color(Palette.paper.opacity(0.18)))
            // The lit part: a half disc plus or minus an ellipse for the terminator.
            var lit = Path()
            let k = CGFloat(1 - 2 * moon.illumination)
            let rightLit = moon.waxing
            lit.addArc(center: p, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: !rightLit)
            let steps = 24
            for i in 0...steps {
                let a = Double.pi / 2 - Double(i) / Double(steps) * Double.pi
                let x = p.x + (rightLit ? 1 : -1) * k * r * CGFloat(cos(a))
                let y = p.y + r * CGFloat(sin(a))
                lit.addLine(to: CGPoint(x: x, y: y))
            }
            lit.closeSubpath()
            ctx.fill(lit, with: .color(Palette.paper))
            ctx.stroke(Path(ellipseIn: disc), with: .color(Palette.paper.opacity(0.6)), lineWidth: 0.75)
            let readout = ctx.resolve(Text(label).font(.osDataSmall).foregroundColor(Palette.paper))
            let w = readout.measure(in: size).width
            let right = p.x + r + 5 + w < size.width - 6
            let y = min(max(p.y, 12), size.height - 12)
            ctx.draw(readout, at: CGPoint(x: right ? p.x + r + 5 : max(p.x - r - 5, w + 6), y: y), anchor: right ? .leading : .trailing)
        } else {
            let left = Bearing.difference(moon.position.azimuth, projector.heading) < 0
            let y = size.height / 2
            let x: CGFloat = left ? 14 : size.width - 14
            var tri = Path()
            if left {
                tri.move(to: CGPoint(x: x - 6, y: y)); tri.addLine(to: CGPoint(x: x + 4, y: y - 6)); tri.addLine(to: CGPoint(x: x + 4, y: y + 6))
            } else {
                tri.move(to: CGPoint(x: x + 6, y: y)); tri.addLine(to: CGPoint(x: x - 4, y: y - 6)); tri.addLine(to: CGPoint(x: x - 4, y: y + 6))
            }
            tri.closeSubpath()
            ctx.fill(tri, with: .color(Palette.paper))
            ctx.draw(Text("Moon \(Int(moon.position.azimuth.rounded()))° · \(Int((moon.illumination * 100).rounded()))% lit").font(.osDataSmall).foregroundColor(Palette.paper),
                     at: CGPoint(x: left ? x + 10 : x - 10, y: y + 16), anchor: left ? .leading : .trailing)
        }
    }
}

/// What Vision saw in a still: the subjects, best first, and whether it looks like an
/// interior or exterior.
struct VisionResult {
    var subjects: [String] = []
    /// "int" or "ext", when Vision is fairly sure.
    var setting: String?
    /// "person", "two people", "a group", when people are in frame.
    var people: String?
    /// A sign or shopfront word Vision could read, if one stands out.
    var sign: String?
    /// A lighting cue from the still's brightness: "practical", "dappled light", "backlit".
    var lightCue: String?
    /// How many separate bright patches the light read found (sun through leaves makes many).
    var brightPatches = 0
    /// Some of the frame clips to near white, like a lamp's bulb.
    var hotCore = false
    /// Furniture, a screen or a lamp is in shot, whatever the setting says.
    var looksIndoor = false
    /// Something says outside: an EXT setting, plants, sky, brick, paving or a fence.
    var looksOutdoor = false
    /// A face fills much of the frame, whatever the lens says.
    var closeUp = false
    /// Shot size from how big the subject is in frame ("close-up", "medium", "full shot"),
    /// when there's a person or a clear subject to measure. Beats the focal-length guess.
    var framing: String?
}

enum VisionLabels {
    /// Classifies the whole still and, separately, the part that draws the eye (Vision's
    /// attention saliency), so a lamp in a dark room isn't drowned out by "room" or
    /// "machine". Scores from the two passes are merged; the subject crop gets a nudge.
    static func see(_ data: Data?) async -> VisionResult {
        guard let data else { return VisionResult() }
        return await Task.detached(priority: .userInitiated) { () -> VisionResult in
            let handler = VNImageRequestHandler(data: data)
            let whole = VNClassifyImageRequest()
            let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
            // People, animals and readable signs say far more about a shot than the scene
            // classifier alone ("two people", "dog", "sign: Bakery").
            let humans = VNDetectHumanRectanglesRequest()
            humans.upperBodyOnly = false
            // Close-ups crop the body away, so faces count people too.
            let faces = VNDetectFaceRectanglesRequest()
            // The classifier has no "hand" label, but the hand-pose detector finds one (even a
            // hand's shadow on a wall), which suits inserts.
            let hands = VNDetectHumanHandPoseRequest()
            hands.maximumHandCount = 2
            let animals = VNRecognizeAnimalsRequest()
            let words = VNRecognizeTextRequest()
            words.recognitionLevel = .fast
            words.usesLanguageCorrection = true
            try? handler.perform([whole, saliency, humans, faces, hands, animals, words])

            // Count people big enough to matter (not specks in the distance).
            let bodies = (humans.results ?? []).filter { $0.confidence > 0.5 && $0.boundingBox.area > 0.01 }
            let faceBoxes = (faces.results ?? []).filter { $0.confidence > 0.6 && $0.boundingBox.area > 0.002 }
            let count = max(bodies.count, faceBoxes.count)
            // A face filling much of the frame is a close-up of someone.
            let closeUp = faceBoxes.contains { $0.boundingBox.area > 0.06 }
            // How big the subject is in frame, the way a DP names shot sizes.
            let biggestFace = faceBoxes.map(\.boundingBox.area).max() ?? 0
            let tallestBody = bodies.map(\.boundingBox.height).max() ?? 0
            let salient = saliency.results?.first?.salientObjects?.map(\.boundingBox.area).max() ?? 0
            let framing: String? =
                biggestFace > 0.12 ? "close-up"
                : biggestFace > 0.04 ? "medium close-up"
                : tallestBody > 0.85 ? "medium"
                : tallestBody > 0.45 ? "full shot"
                : (bodies.isEmpty && faceBoxes.isEmpty && salient > 0.45) ? "close"
                : nil
            let people: String? = switch count {
            case 0: nil
            case 1: "person"
            case 2: "two people"
            case 3: "three people"
            default: "a group"
            }

            let animal = (animals.results ?? [])
                .compactMap { $0.labels.first }
                .filter { $0.confidence > 0.6 }
                .max { $0.confidence < $1.confidence }?
                .identifier.lowercased()

            // The largest confident line of text, 3 to 24 characters, as a sign.
            let sign = (words.results ?? [])
                .filter { ($0.topCandidates(1).first?.confidence ?? 0) > 0.8 }
                .compactMap { o -> (String, CGFloat)? in
                    guard let t = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines),
                          (3...24).contains(t.count), t.contains(where: \.isLetter) else { return nil }
                    return (t, o.boundingBox.height)
                }
                .max { $0.1 < $1.1 }?.0

            var scores: [String: Float] = [:]
            for o in whole.results ?? [] { scores[o.identifier] = o.confidence }

            // Classify the most eye-catching region on its own.
            if let box = saliency.results?.first?.salientObjects?.max(by: { $0.boundingBox.area < $1.boundingBox.area })?.boundingBox,
               box.area > 0.02, box.area < 0.9 {
                let subject = VNClassifyImageRequest()
                subject.regionOfInterest = box.insetBy(dx: -box.width * 0.1, dy: -box.height * 0.1)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                try? handler.perform([subject])
                for o in subject.results ?? [] {
                    scores[o.identifier] = max(scores[o.identifier] ?? 0, o.confidence * 1.15)
                }
            }

            // Vision has "interior_room" and "outdoor" but no "indoor". A bright laptop screen
            // can score "outdoor", so furniture and screens rule EXT out.
            let inside = scores["interior_room"] ?? 0
            let outside = scores["outdoor"] ?? 0
            let indoorCues = ["table", "desk", "bookshelf", "cabinet", "computer", "laptop", "bed", "sofa", "couch", "chair", "lamp"]
            let looksIndoor = indoorCues.contains { (scores[$0] ?? 0) > 0.25 }
            let setting: String? = max(inside, outside) < 0.3 ? nil
                : inside > outside ? "INT"
                : looksIndoor ? nil : "EXT"

            // Parents share their child's score (machine = computer = laptop), so on a tie
            // the longer, more specific identifier wins once the parents are skipped.
            let ranked = scores
                .filter { $0.value >= 0.25 }
                .sorted { abs($0.value - $1.value) > 0.001 ? $0.value > $1.value : $0.key.count > $1.key.count }
                .map(\.key)
            // Outdoors a bright patch is sky or sun, not a lamp (a robin against the sky
            // read as a practical); keep dappled and backlit there. Long-lens stills of birds
            // and plants often don't score "outdoor" at all, so nature labels count too.
            let nature = ["bird", "plant", "tree", "foliage", "flower", "grass", "sky", "animal"]
            let looksNatural = setting != "INT" && nature.contains { (scores[$0] ?? 0) >= 0.1 }
            let outdoorCues = nature + ["brick", "sidewalk", "pavement", "road", "street", "fence", "garden"]
            let looksOutdoor = setting == "EXT" || outdoorCues.contains { (scores[$0] ?? 0) >= 0.1 }
            let light = LightCues.read(data, labels: scores)
            var cue = light.cue
            if cue == "practical", (outside > 0.3 && inside < outside) || looksNatural { cue = nil }
            var subjects = Captioner.readable(ranked)
            // Never come back empty: the best label Vision had, however unsure.
            if subjects.isEmpty {
                let weak = scores.filter { $0.value >= 0.03 }.sorted { $0.value > $1.value }.map(\.key)
                subjects = Array(Captioner.readable(weak).prefix(1))
            }
            if let animal, !subjects.contains(animal) { subjects.insert(animal, at: 0) }
            // A hand with no face or body in frame is an insert: lead with it.
            if count == 0, (hands.results ?? []).contains(where: { $0.confidence > 0.8 }) {
                subjects.removeAll { $0 == "hand" }
                subjects.insert("hand", at: 0)
            }
            // The animal detector only knows cats and dogs, and the classifier names birds by
            // species, often wrongly (a robin came back "sparrow"), so just say "bird".
            if (scores["bird"] ?? 0) >= 0.1 {
                subjects.removeAll { $0 == "bird" || $0 == "sparrow" }
                subjects.insert("bird", at: 0)
            }
            // Vision often says "people" or "adult" for crowds; the count above says it better.
            if people != nil { subjects.removeAll { ["person", "people", "adult", "child", "crowd"].contains($0) } }
            return VisionResult(subjects: Array(subjects.prefix(4)), setting: setting, people: people, sign: sign,
                                lightCue: cue, brightPatches: light.patches, hotCore: light.hotCore, looksIndoor: looksIndoor, looksOutdoor: looksOutdoor,
                                closeUp: closeUp, framing: framing)
        }.value
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

/// Lighting a DP would note that the classifier never will: a lamp glowing in a dark room
/// (a practical), patches of sun on a dark surface, or a bright window in a dark frame.
/// Read from a 160-pixel copy of the still, brightness as the brightest of R, G and B so
/// warm lamps count. Thresholds tuned on Elliot's recce stills (2 Oct 2026).
enum LightCues {
    static func read(_ data: Data, labels: [String: Float]) -> (cue: String?, patches: Int, hotCore: Bool) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return (nil, 0, false) }
        let w = thumb.width, h = thumb.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return (nil, 0, false) }
        ctx.draw(thumb, in: CGRect(x: 0, y: 0, width: w, height: h))

        let n = w * h
        var lum = [UInt8](repeating: 0, count: n)
        var total = 0.0
        for i in 0..<n {
            let v = max(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2])
            lum[i] = v
            total += Double(v)
        }
        let mean = total / Double(n) / 255

        // Separate bright patches (over 200) and their share of the frame.
        var seen = [Bool](repeating: false, count: n)
        var blobs: [Double] = []
        for start in 0..<n where lum[start] > 200 && !seen[start] {
            var size = 0
            var stack = [start]
            seen[start] = true
            while let i = stack.popLast() {
                size += 1
                let x = i % w, y = i / w
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                    let j = ny * w + nx
                    if lum[j] > 200, !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            let share = Double(size) / Double(n)
            if share >= 0.001 { blobs.append(share) }
        }
        guard let largest = blobs.max() else { return (nil, 0, false) }
        // A lamp's core clips to near white; sun pools on paving are mid-bright and soft.
        let hot = lum.contains { $0 >= 250 }

        // A window has to be a confident label: laptop wallpaper and doors score ~0.3.
        let windowish = ["window", "door", "sky", "sun", "sunset_sunrise"].contains { (labels[$0] ?? 0) >= 0.45 }
        // Dappled first: sun patches on a cupboard door shouldn't read as a backlit door.
        if blobs.count >= 4, mean < 0.3 { return ("dappled light", blobs.count, hot) }
        if windowish || largest >= 0.1 { return ("backlit", blobs.count, hot) }
        let real = blobs.filter { $0 >= 0.005 }
        if mean < 0.45, (1...2).contains(real.count), largest <= 0.10 { return ("practical", blobs.count, hot) }
        return (nil, blobs.count, hot)
    }
}
