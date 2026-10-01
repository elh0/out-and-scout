import SwiftUI
import Vision

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

    @State private var focusPoint: CGPoint?
    @State private var focusShownAt = Date.distantPast

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let frame = store.aspect.isFull ? CGRect(origin: .zero, size: size) : FrameMath.fit(aspect: store.aspect.value, in: size)

            ZStack(alignment: .topLeading) {
                cameraLayer

                if !store.aspect.isFull {
                    AspectMask(frame: frame)
                }

                if store.overlays.grid {
                    ThirdsGrid().frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                }
                if store.overlays.level {
                    LevelLine(roll: motion.roll).frame(width: frame.width, height: frame.height).offset(x: frame.minX, y: frame.minY)
                }
                if store.overlays.sunPath, let heading = location.heading {
                    SunPathOverlay(
                        sunDay: sunDay,
                        sun: sun,
                        projector: Projector(heading: heading, elevation: motion.cameraElevation, hfov: camera.previewHFOV, size: size)
                    )
                }

                hud.offset(x: frame.minX + Space.xs, y: frame.minY + Space.xs)

                if let p = focusPoint {
                    FocusSquare(locked: camera.aeAfLocked, bias: camera.exposureBias) { camera.setExposureBias($0) }
                        .position(p)
                        .id(focusShownAt)
                        .task(id: focusShownAt) {
                            guard (try? await Task.sleep(for: .seconds(3))) != nil else { return }
                            if !camera.aeAfLocked && camera.exposureBias == 0 { focusPoint = nil }
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { p in
                camera.focus(atLayerPoint: p)
                showFocus(at: p)
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                // SwiftUI's long press doesn't report a location; lock where the last tap was, or the centre.
                let p = focusPoint ?? CGPoint(x: size.width / 2, y: size.height / 2)
                camera.lock(atLayerPoint: p)
                showFocus(at: p)
            }
            .onAppear { syncLens(size: size, frame: frame) }
            .onChange(of: LensKey(lens: store.lensMM, kit: store.kit, aspect: store.aspect.value, size: size)) {
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
            placeholder("camera access is off. turn it on in settings to frame shots.", settingsButton: true)
        case .unavailable:
            placeholder("no camera here. pins still work, without a still.", settingsButton: false)
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
                Link("open settings", destination: url)
                    .buttonStyle(PillButtonStyle(kind: .secondary, onDark: true))
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x1A1A18))
    }

    /// Three readouts, max: lens, time, bearing.
    private var hud: some View {
        HStack(spacing: Space.s) {
            Text("\(Int(store.lensMM.rounded()))mm")
            Text(Format.time(planned))
                .foregroundStyle(store.plannedMinutes == nil ? Palette.sun : Palette.paper)
            Text(location.heading.map(Format.bearing) ?? "—")
        }
        .font(.osData)
        .foregroundStyle(Palette.paper)
        .padding(.horizontal, Space.xs)
        .padding(.vertical, Space.xxs + 1)
        .background(Palette.hud, in: RoundedRectangle(cornerRadius: Radius.readout))
    }

    private func showFocus(at p: CGPoint) {
        focusPoint = p
        focusShownAt = Date()
    }

    private func syncLens(size: CGSize, frame: CGRect) {
        guard size.width > 0 else { return }
        // The lens's field of view spans the whole 16:9 viewfinder, which is what every
        // still keeps, so changing frame lines later never changes the lens framing.
        frameFraction = 1
        camera.match(targetHFOV: store.kit.horizontalFOV(focal: store.lensMM), frameFraction: 1)
    }

    private struct LensKey: Equatable {
        var lens: Double
        var kit: Kit
        var aspect: Double
        var size: CGSize
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
            ctx.stroke(Path(frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(Palette.paper.opacity(0.5)), lineWidth: 1)
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
                        Text("ae/af lock")
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

/// The day's sun arc, golden-hour stretch highlighted, and the sun at the chosen time.
/// If the sun is off-screen, an edge marker says which way to turn.
struct SunPathOverlay: View {
    let sunDay: SunDay?
    let sun: SunPosition
    let projector: Projector

    var body: some View {
        Canvas { ctx, size in
            if let day = sunDay {
                var arc = Path()
                var golden = Path()
                var started = false
                var goldenStarted = false
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
                }
                ctx.stroke(arc, with: .color(Palette.paper.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ctx.stroke(golden, with: .color(Palette.sun.opacity(0.6)), lineWidth: 2)

                // Horizon
                if let l = projector.point(azimuth: projector.heading - 80, elevation: 0),
                   let r = projector.point(azimuth: projector.heading + 80, elevation: 0) {
                    var h = Path()
                    h.move(to: CGPoint(x: 0, y: l.y)); h.addLine(to: CGPoint(x: size.width, y: r.y))
                    ctx.stroke(h, with: .color(Palette.paper.opacity(0.2)), lineWidth: 0.5)
                }
            }

            if let p = projector.point(azimuth: sun.azimuth, elevation: sun.elevation),
               CGRect(origin: .zero, size: size).insetBy(dx: -8, dy: -8).contains(p) {
                let r: CGFloat = 7
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                if sun.elevation > -0.8 {
                    ctx.fill(dot, with: .color(Palette.sun))
                } else {
                    ctx.stroke(dot, with: .color(Palette.sun), lineWidth: 1.5)
                }
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
                let label = Text("sun \(Int(sun.azimuth.rounded()))°").font(.osDataSmall).foregroundColor(Palette.paper)
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
            try? handler.perform([whole, saliency])

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

            // Vision has "interior_room" and "outdoor" but no "indoor".
            let inside = scores["interior_room"] ?? 0
            let outside = scores["outdoor"] ?? 0
            let setting: String? = max(inside, outside) < 0.3 ? nil : (inside > outside ? "int" : "ext")

            // Parents share their child's score (machine = computer = laptop), so on a tie
            // the longer, more specific identifier wins once the parents are skipped.
            let ranked = scores
                .filter { $0.value >= 0.25 }
                .sorted { abs($0.value - $1.value) > 0.001 ? $0.value > $1.value : $0.key.count > $1.key.count }
                .map(\.key)
            return VisionResult(subjects: Array(Captioner.readable(ranked).prefix(4)), setting: setting)
        }.value
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
