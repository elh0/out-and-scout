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
            let frame = FrameMath.fit(aspect: lineAspect, in: inset(size).size)
                .offsetBy(dx: inset(size).minX, dy: inset(size).minY)

            ZStack(alignment: .topLeading) {
                cameraLayer

                AspectMask(frame: frame)

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
                        projector: Projector(heading: heading, elevation: motion.cameraElevation, hfov: camera.previewHFOV, size: size)
                    )
                }

                // Ratio and lens in the frame's bottom-left corner, like the v3c prototype.
                // Time and bearing live in the top bar now.
                Text("\(store.aspect.display) · \(Format.mm(store.lensMM))mm")
                    .font(.osDataSmall)
                    .foregroundStyle(Palette.paper.opacity(0.7))
                    .fixedSize()
                    .offset(x: frame.minX + Space.xs, y: frame.maxY - 20)

                // Portrait board: the sun's height in the frame's top-right corner.
                if portrait, sun.elevation > 0 {
                    Text("Sun \(Int(sun.elevation.rounded()))° up")
                        .font(.osDataSmall)
                        .foregroundStyle(Palette.paper)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.night.opacity(0.72), in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .frame(width: frame.width - 16, alignment: .trailing)
                        .offset(x: frame.minX + 8, y: frame.minY + 8)
                }

                // Honest about the phone's limit: say how wide it can really go here.
                if camera.isTooWide, camera.status == .running {
                    Text("Wider than the iPhone can see · widest here ≈ \(widestFocal(size: size, frame: frame))mm")
                        .font(.osDataSmall)
                        .foregroundStyle(Palette.paper)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.hud, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .frame(width: frame.width)
                        // Upright, the sun's height sits top-right, so this goes near the bottom.
                        .offset(x: frame.minX, y: portrait ? frame.maxY - 44 : frame.minY + Space.xs)
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
                camera.focus(atLayerPoint: p)
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
                camera.lock(atLayerPoint: p)
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

    /// A small margin so even the widest ratio reads as a frame rather than full bleed.
    /// Portrait follows the board: 24 each side, 5 top and bottom.
    private func inset(_ size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: portrait ? 24 : 10, dy: portrait ? 5 : 8)
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
        let fraction = Double(frame.width / size.width)
        camera.match(targetHFOV: linesHFOV, frameFraction: fraction)
        // The still keeps the whole sensor frame, which is 1/r times as wide as the lines.
        frameFraction = min(fraction / r, 1)
    }

    /// The widest cine focal length the phone can show truthfully in these frame lines.
    private func widestFocal(size: CGSize, frame: CGRect) -> String {
        guard size.width > 0 else { return "—" }
        let linesMax = camera.widestHFOV(frameFraction: Double(frame.width / size.width))
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

    var body: some View {
        Canvas { ctx, size in
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addRect(frame)
            ctx.fill(outside, with: .color(Palette.hud), style: FillStyle(eoFill: true))
            ctx.stroke(Path(frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(Palette.paper.opacity(0.85)), lineWidth: 1)
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

            if let p = projector.point(azimuth: sun.azimuth, elevation: sun.elevation),
               bounds.insetBy(dx: -8, dy: -8).contains(p) {
                let r: CGFloat = 7
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(Palette.sun))
                let readout = ctx.resolve(Text("Az \(Int(sun.azimuth.rounded()))° · El \(Int(sun.elevation.rounded()))°")
                    .font(.osDataSmall).foregroundColor(Palette.paper))
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
            let animals = VNRecognizeAnimalsRequest()
            let words = VNRecognizeTextRequest()
            words.recognitionLevel = .fast
            words.usesLanguageCorrection = true
            try? handler.perform([whole, saliency, humans, faces, animals, words])

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

            // A small bird isn't what the frame is about, so the whole-frame classifier misses
            // it (a robin on a sink ledge at 40mm came back "brick"). Look again in each salient
            // region and in five overlapping half-size crops, for birds only, and only trust
            // a confident score so branches don't turn into birds.
            var smallBird = false
            if (scores["bird"] ?? 0) < 0.1 {
                var crops = (saliency.results?.first?.salientObjects ?? []).map(\.boundingBox).filter { $0.area > 0.002 }
                for x in [0.0, 0.5] { for y in [0.0, 0.5] { crops.append(CGRect(x: x, y: y, width: 0.5, height: 0.5)) } }
                crops.append(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
                let looks = crops.map { r -> VNClassifyImageRequest in
                    let q = VNClassifyImageRequest()
                    q.regionOfInterest = r
                    return q
                }
                try? handler.perform(looks)
                smallBird = looks.contains { ($0.results ?? []).contains { $0.identifier == "bird" && $0.confidence >= 0.3 } }
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
            let looksNatural = setting != "INT" && (smallBird || nature.contains { (scores[$0] ?? 0) >= 0.1 })
            var cue = LightCues.read(data, labels: scores)
            if cue == "practical", (outside > 0.3 && inside < outside) || looksNatural { cue = nil }
            var subjects = Captioner.readable(ranked)
            // Never come back empty: the best label Vision had, however unsure.
            if subjects.isEmpty {
                let weak = scores.filter { $0.value >= 0.03 }.sorted { $0.value > $1.value }.map(\.key)
                subjects = Array(Captioner.readable(weak).prefix(1))
            }
            if let animal, !subjects.contains(animal) { subjects.insert(animal, at: 0) }
            // The animal detector only knows cats and dogs, and the classifier names birds by
            // species, often wrongly (a robin came back "sparrow"), so just say "bird".
            if smallBird || (scores["bird"] ?? 0) >= 0.1 {
                subjects.removeAll { $0 == "bird" || $0 == "sparrow" }
                subjects.insert("bird", at: 0)
            }
            // Vision often says "people" or "adult" for crowds; the count above says it better.
            if people != nil { subjects.removeAll { ["person", "people", "adult", "child", "crowd"].contains($0) } }
            return VisionResult(subjects: Array(subjects.prefix(4)), setting: setting, people: people, sign: sign,
                                lightCue: cue,
                                // The wall behind a small bird fills the saliency map; that's
                                // not a close shot, so let the lens name the size.
                                closeUp: closeUp, framing: smallBird ? nil : framing)
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
    static func read(_ data: Data, labels: [String: Float]) -> String? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 160,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let w = thumb.width, h = thumb.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &rgba, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
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
        guard let largest = blobs.max() else { return nil }

        // A window has to be a confident label: laptop wallpaper and doors score ~0.3.
        let windowish = ["window", "door", "sky", "sun", "sunset_sunrise"].contains { (labels[$0] ?? 0) >= 0.45 }
        // Dappled first: sun patches on a cupboard door shouldn't read as a backlit door.
        if blobs.count >= 4, mean < 0.3 { return "dappled light" }
        if windowish || largest >= 0.1 { return "backlit" }
        let real = blobs.filter { $0 >= 0.005 }
        if mean < 0.45, (1...2).contains(real.count), largest <= 0.10 { return "practical" }
        return nil
    }
}
