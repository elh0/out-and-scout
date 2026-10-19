import SwiftUI

// The sky sweep (Elliot, 19 Oct 2026; mock https://claude.ai/artifact/LXqafdSMKh3keDhs2igaQq):
// offered after the first shot at a spot, ten seconds following the sun's path, then
// "be here 16:10, the sun clears the roof 16:20". The line can be fixed by hand.

/// Drawn over the live picture while sweeping: today's sun path dashed, the part already
/// looked at solid, the sky line traced so far, a ring in the middle and a dot on the next
/// bit of path to look at (an arrow at the edge when it's off screen).
struct SkySweepOverlay: View {
    let sweep: SkySweep
    let projector: Projector

    var body: some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            var all = Path(), done = Path()
            var startedAll = false, startedDone = false
            var hours: [(CGPoint, Int)] = []
            let cal = Calendar.current
            let target = sweep.target
            for s in sweep.path {
                guard let p = projector.point(azimuth: s.position.azimuth, elevation: s.position.elevation) else {
                    startedAll = false; startedDone = false; continue
                }
                if startedAll { all.addLine(to: p) } else { all.move(to: p); startedAll = true }
                let looked = target.map { s.time < $0.time } ?? true
                if looked {
                    if startedDone { done.addLine(to: p) } else { done.move(to: p); startedDone = true }
                } else {
                    startedDone = false
                }
                let c = cal.dateComponents([.hour, .minute], from: s.time)
                if c.minute == 0, bounds.contains(p) { hours.append((p, c.hour ?? 0)) }
            }
            ctx.stroke(all, with: .color(Palette.sun.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 5]))
            ctx.stroke(done, with: .color(Palette.sun), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            for (p, h) in hours {
                ctx.draw(Text(String(format: "%02d", h)).font(Fonts.mono(9)).foregroundColor(Palette.paper.opacity(0.8)),
                         at: CGPoint(x: p.x, y: p.y - 8), anchor: .bottom)
            }

            // The sky line so far.
            if let line = sweep.traced {
                var l = Path()
                var started = false
                for pt in line.points {
                    guard let p = projector.point(azimuth: pt.azimuth, elevation: pt.elevation) else { started = false; continue }
                    if started { l.addLine(to: p) } else { l.move(to: p); started = true }
                }
                ctx.stroke(l, with: .color(Palette.paper), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }

            // The ring to keep the path in.
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 28, y: c.y - 28, width: 56, height: 56)), with: .color(Palette.paper), lineWidth: 1)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Palette.paper))

            // Where to look next.
            if let t = target {
                if let p = projector.point(azimuth: t.position.azimuth, elevation: t.position.elevation),
                   bounds.insetBy(dx: 6, dy: 6).contains(p) {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(Palette.sun))
                } else {
                    let dx = Bearing.difference(t.position.azimuth, projector.heading)
                    let dy = t.position.elevation - projector.elevation
                    let len = max(hypot(dx, dy), 0.001)
                    let ux = dx / len, uy = -dy / len
                    // From the centre out towards the target, stopping short of the edge.
                    let reach = min(size.width / 2 - 24, size.height / 2 - 24)
                    let tip = CGPoint(x: c.x + ux * reach, y: c.y + uy * reach)
                    var tri = Path()
                    tri.move(to: CGPoint(x: tip.x + ux * 8, y: tip.y + uy * 8))
                    tri.addLine(to: CGPoint(x: tip.x - uy * 6, y: tip.y + ux * 6))
                    tri.addLine(to: CGPoint(x: tip.x + uy * 6, y: tip.y - ux * 6))
                    tri.closeSubpath()
                    ctx.fill(tri, with: .color(Palette.sun))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The words and buttons over the sweep: what to do, how far along, Cancel and Done.
struct SkySweepHUD: View {
    @Environment(ScoutStore.self) private var store
    let sweep: SkySweep

    var body: some View {
        VStack(spacing: 0) {
            Text(hint.uppercased())
                .font(Fonts.mono(9))
                .tracking(0.6)
                .foregroundStyle(Palette.paper)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Sheet.bg.opacity(0.7), in: Capsule())
                .padding(.top, 10)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                OPill(label: "Cancel", size: .small) { store.sweep = nil }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.paper.opacity(0.18))
                        Capsule().fill(Palette.paper).frame(width: g.size.width * min(1, sweep.progress / 0.9))
                    }
                }
                .frame(height: 2)
                OPill(label: "Done", on: sweep.progress >= 0.5, size: .small) {
                    if sweep.progress >= 0.5 { store.finishSweep() }
                }
                .opacity(sweep.progress >= 0.5 ? 1 : 0.4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    private var hint: String {
        if sweep.progress < 0.05 { return "Point at the orange dot, then follow the sun's path" }
        if sweep.progress < 0.5 { return "Keep the sun's path in the ring" }
        return "Nearly there"
    }
}

/// After the first shot at a spot: "The sun crosses this view from 15:40. Sweep its path to
/// see when it clears the roofs · 10 s", with Skip and Sweep.
struct SweepOfferCard: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    let sceneID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (Text("The sun crosses this view\(from). ") + Text("Sweep its path to see when it clears the roofs.").foregroundColor(Sheet.muted))
                .font(Fonts.mono(11))
                .foregroundStyle(Palette.paper)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                OPill(label: "Skip", size: .small) { store.skipSweep(sceneID) }
                Button {
                    let c = location.coordinate
                    if let b = motion.heading ?? location.heading {
                        store.startSweep(sceneID, bearing: b, latitude: c.latitude, longitude: c.longitude)
                    }
                } label: {
                    Text("Sweep · 10 s")
                        .font(Fonts.mono(10))
                        .foregroundStyle(Sheet.bg)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Palette.sun, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(OPressRing())
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .background(Outline.card.opacity(0.92), in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Outline.line.opacity(0.5), lineWidth: 1))
    }

    /// " from 15:40" when the low sun is still to come.
    private var from: String {
        let c = location.coordinate
        guard let b = motion.heading ?? location.heading,
              let path = SkySweep.pathToSweep(latitude: c.latitude, longitude: c.longitude, bearing: b, on: Date()),
              let first = path.first?.time, first > Date() else { return "" }
        return " from \(Format.time(first))"
    }
}

/// "Be here 16:10 · Sun clears 16:20 · Golden from 16:59 · Behind 17:28 · Sunset 17:56"
struct SkyReadRow: View {
    let read: SkyRead

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.bits(read).enumerated()), id: \.offset) { _, b in
                VStack(alignment: .leading, spacing: 3) {
                    Text(b.label.uppercased()).font(Fonts.mono(8)).tracking(0.6).foregroundStyle(Sheet.muted)
                    Text(b.value).font(Fonts.mono(12)).foregroundStyle(b.sun ? Palette.sun : Palette.paper)
                }
                .fixedSize()
            }
        }
    }

    static func bits(_ r: SkyRead) -> [(label: String, value: String, sun: Bool)] {
        var out: [(String, String, Bool)] = []
        if let b = r.beHere { out.append(("Be here", Format.time(b), false)) }
        if let c = r.clears { out.append(("Sun clears", Format.time(c), true)) }
        if let g = r.goldenStart { out.append(("Golden from", Format.time(g), true)) }
        if let h = r.hides { out.append(("Behind", Format.time(h), false)) }
        if let s = r.sunset { out.append(("Sunset", Format.time(s), false)) }
        return out.map { (label: $0.0, value: $0.1, sun: $0.2) }
    }
}

/// The result, straight after a sweep: the times, with Redo, Fix the line and Done.
struct SweepResultCard: View {
    @Environment(ScoutStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(MotionService.self) private var motion
    let scene: ScoutScene

    var body: some View {
        if let sky = scene.skyline {
            let read = SkyRead.read(sky, on: Date())
            VStack(alignment: .leading, spacing: 10) {
                Text(read.summary).font(Fonts.mono(11)).foregroundStyle(Palette.paper)
                ScrollView(.horizontal, showsIndicators: false) { SkyReadRow(read: read) }
                HStack(spacing: 8) {
                    OPill(label: "Redo", size: .small) {
                        let c = location.coordinate
                        if let b = motion.heading ?? location.heading {
                            store.startSweep(scene.id, bearing: b, latitude: c.latitude, longitude: c.longitude)
                        }
                    }
                    OPill(label: "Fix the line", size: .small) {
                        store.sweepResult = nil
                        store.editingSkyline = scene.id
                    }
                    Spacer(minLength: 0)
                    OPill(label: "Done", on: true, size: .small) { store.sweepResult = nil }
                }
            }
            .padding(14)
            .frame(maxWidth: 460)
            .background(Outline.card.opacity(0.92), in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Outline.line.opacity(0.5), lineWidth: 1))
        }
    }
}

/// Fix the line by hand: the sky line and today's sun across it, with dots to drag up or
/// down. Also the way to correct a sweep a tree or a lamppost fooled.
struct SkylineEditor: View {
    @Environment(ScoutStore.self) private var store
    let scene: ScoutScene

    @State private var line: Skyline?
    /// The line as it was when a drag began, so the drag moves it from there.
    @State private var dragBase: Skyline?
    @State private var original: Skyline?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FIX THE SKY LINE").font(Fonts.mono(9)).tracking(0.8).foregroundStyle(Sheet.muted)
                    Text(scene.name).font(Fonts.mono(13)).foregroundStyle(Palette.paper).lineLimit(1)
                }
                Spacer(minLength: 0)
                OPill(label: "Reset", size: .small) { line = original }
                OPill(label: "Cancel", size: .small) { store.editingSkyline = nil }
                OPill(label: "Done", on: true, size: .small) {
                    if var l = line {
                        if l != original { l.edited = true }
                        store.setSkyline(scene.id, to: l)
                    }
                    store.editingSkyline = nil
                }
            }
            if let l = line {
                chart(l)
                ScrollView(.horizontal, showsIndicators: false) { SkyReadRow(read: SkyRead.read(l, on: Date())) }
                Text("Drag the dots up or down to match the roofline.")
                    .font(Fonts.mono(9)).foregroundStyle(Sheet.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
        .background(Sheet.bg.ignoresSafeArea())
        .onAppear {
            line = scene.skyline
            original = scene.skyline
        }
    }

    private struct Frame {
        var az0: Double, az1: Double, el0: Double, el1: Double, size: CGSize
        func point(_ az: Double, _ el: Double) -> CGPoint {
            CGPoint(x: (az - az0) / (az1 - az0) * size.width, y: (1 - (el - el0) / (el1 - el0)) * size.height)
        }
        func elevation(y: CGFloat) -> Double { el0 + (1 - Double(y / max(size.height, 1))) * (el1 - el0) }
    }

    private func chart(_ l: Skyline) -> some View {
        GeometryReader { g in
            let lo = (l.first ?? 0) - 3, hi = (l.last ?? 0) + 3
            let path = sunPath(l).filter { $0.az >= lo && $0.az <= hi }
            let top = min(45, max(l.points.map(\.elevation).max() ?? 10, path.map(\.el).max() ?? 10) + 3)
            let f = Frame(az0: lo, az1: hi, el0: -2, el1: top, size: g.size)
            let handles = handleIndices(l)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                        Gradient(colors: [Color(hex: 0x4F6480), Color(hex: 0xA7A7A0), Color(hex: 0xE0AE78)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    var ground = Path()
                    ground.move(to: CGPoint(x: 0, y: size.height))
                    for p in l.points { ground.addLine(to: f.point(p.azimuth, p.elevation)) }
                    ground.addLine(to: CGPoint(x: size.width, y: f.point(hi, l.points.last?.elevation ?? 0).y))
                    ground.addLine(to: CGPoint(x: size.width, y: size.height))
                    ground.closeSubpath()
                    ctx.fill(ground, with: .color(Color(hex: 0x1B1916)))
                    var edge = Path()
                    for (i, p) in l.points.enumerated() {
                        let q = f.point(p.azimuth, p.elevation)
                        if i == 0 { edge.move(to: q) } else { edge.addLine(to: q) }
                    }
                    ctx.stroke(edge, with: .color(Palette.paper), lineWidth: 1.2)
                    // The sun: solid where it reaches the spot, dashed where it's behind something.
                    var prev: (CGPoint, Bool)?
                    for s in path {
                        let q = f.point(s.az, s.el)
                        let lit = s.el > (l.elevation(at: s.az) ?? -90)
                        if let pv = prev {
                            let pl = pv.1
                            var seg = Path(); seg.move(to: pv.0); seg.addLine(to: q)
                            ctx.stroke(seg, with: .color(pl ? Palette.sun : Palette.paper.opacity(0.5)),
                                       style: StrokeStyle(lineWidth: pl ? 2.2 : 1.2, lineCap: .round, dash: pl ? [] : [3, 4]))
                        }
                        prev = (q, lit)
                        if Calendar.current.component(.minute, from: s.time) == 0 {
                            ctx.draw(Text(Format.time(s.time)).font(Fonts.mono(8)).foregroundColor(Palette.paper.opacity(0.85)),
                                     at: CGPoint(x: q.x, y: q.y - 8), anchor: .bottom)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.readout))

                ForEach(handles, id: \.self) { i in
                    let q = f.point(l.points[i].azimuth, l.points[i].elevation)
                    Circle()
                        .fill(Sheet.bg)
                        .overlay(Circle().strokeBorder(Palette.paper, lineWidth: 1.2))
                        .frame(width: 9, height: 9)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                        .position(q)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if dragBase == nil { dragBase = line }
                                    guard let base = dragBase else { return }
                                    let target = f.elevation(y: v.location.y)
                                    line = drag(base, handle: i, handles: handles, to: max(-1, min(top, target)))
                                }
                                .onEnded { _ in dragBase = nil }
                        )
                }
            }
        }
    }

    /// About fourteen dots along the line, plus the ends.
    private func handleIndices(_ l: Skyline) -> [Int] {
        let n = l.points.count
        guard n > 2 else { return Array(0..<n) }
        let step = max(1, n / 14)
        var out = Array(stride(from: 0, to: n, by: step))
        if out.last != n - 1 { out.append(n - 1) }
        return out
    }

    /// Moves one dot to `elevation`; the line between it and the dots either side follows,
    /// less the further it is from the dot, so the roofline's shape keeps.
    private func drag(_ base: Skyline, handle i: Int, handles: [Int], to elevation: Double) -> Skyline {
        var out = base
        let delta = elevation - base.points[i].elevation
        let k = handles.firstIndex(of: i) ?? 0
        let left = k > 0 ? handles[k - 1] : i
        let right = k < handles.count - 1 ? handles[k + 1] : i
        for j in left...right {
            let w: Double
            if j == i { w = 1 }
            else if j < i { w = Double(j - left) / Double(max(i - left, 1)) }
            else { w = Double(right - j) / Double(max(right - i, 1)) }
            out.points[j].elevation = base.points[j].elevation + delta * w
        }
        return out
    }

    private struct SunPt { var az: Double; var el: Double; var time: Date }

    /// Today's sun at the spot, every two minutes while it's up, azimuths unwrapped to the line's.
    private func sunPath(_ l: Skyline) -> [SunPt] {
        let day = SunCalculator.day(containing: Date(), latitude: l.latitude, longitude: l.longitude)
        let base = (l.first ?? 0) - 90
        return day.samples.filter { $0.position.elevation > -1 }.map {
            SunPt(az: Skyline.unwrap($0.position.azimuth, from: base), el: $0.position.elevation, time: $0.time)
        }.sorted { $0.az < $1.az }
    }
}
