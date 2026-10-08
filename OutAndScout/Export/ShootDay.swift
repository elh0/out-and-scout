import CoreLocation
import MapKit
import UIKit

// Page one of the Detailed PDF, outline look round 4 (locked 8 Oct 2026): the shoot day.
// The day's weather, then a plan that takes each place in the order its light comes round,
// with the drive between. Each place's map follows on its own scene page.
extension Exporter {
    struct PlanStop {
        var scene: ScoutScene
        var loc: ShotLocation
        /// The way the first shot faced, for the map's wedge.
        var heading: Double?
        var lensMM: Double?
        /// The scene's number in the export, from 1.
        var number: Int
        var start: Date
        var end: Date
        var light: LightClass?
        /// "golden hour, ¾ back"
        var why: String
        /// Minutes to drive to the next stop, or nil for the last.
        var driveNext: Int?
    }

    /// One place at a time: each scene gets its best light that still fits after the last
    /// stop and the drive there. Scenes with no saved place or shots are left out.
    static func dayPlan(_ scenes: [ScoutScene], on date: Date) -> [PlanStop] {
        struct Want { var scene: ScoutScene; var number: Int; var loc: ShotLocation; var best: LightRead.Best?; var golden: ClosedRange<Date>? }
        var wants: [Want] = []
        for (i, sc) in scenes.enumerated() where !sc.shots.isEmpty {
            guard let loc = place(of: sc) else { continue }
            let day = SunCalculator.day(containing: date, latitude: loc.latitude, longitude: loc.longitude)
            let heading = sc.shots.lazy.compactMap(\.bearing).first
            let best = heading.flatMap { LightRead.best(day: day, heading: $0) }
            wants.append(Want(scene: sc, number: i + 1, loc: loc, best: best, golden: LightRead.golden(day)))
        }
        func window(_ w: Want) -> (start: Date, end: Date)? {
            if let b = w.best { return (b.start, b.end) }
            if let g = w.golden { return (g.lowerBound, g.upperBound) }
            return nil
        }
        // Earliest light first, then walk the day.
        wants.sort { (window($0)?.start ?? .distantFuture) < (window($1)?.start ?? .distantFuture) }
        var stops: [PlanStop] = []
        var free = Date.distantPast
        var prev: ShotLocation?
        for w in wants {
            let drive = prev.map { driveMinutes(from: $0, to: w.loc) } ?? 0
            let ready = free == .distantPast ? free : free.addingTimeInterval(TimeInterval(drive * 60))
            guard let win = window(w) else { continue }
            let start = max(win.start, ready)
            // Never shorter than half an hour, even if the light has moved on.
            let end = max(min(win.end, start.addingTimeInterval(3600)), start.addingTimeInterval(1800))
            if !stops.isEmpty { stops[stops.count - 1].driveNext = drive }
            stops.append(PlanStop(scene: w.scene, loc: w.loc, heading: w.scene.shots.lazy.compactMap(\.bearing).first,
                                  lensMM: w.scene.shots.first?.lensMM, number: w.number, start: start, end: end,
                                  light: w.best?.light, why: w.best?.why ?? "golden hour", driveNext: nil))
            free = end
            prev = w.loc
        }
        return stops
    }

    /// A rough drive: straight-line distance, a third longer by road, at 30 km/h in town;
    /// rounded up to five minutes, never under five.
    static func driveMinutes(from a: ShotLocation, to b: ShotLocation) -> Int {
        let m = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let minutes = m * 1.3 / 1000 / 30 * 60
        return max(5, Int((minutes / 5).rounded(.up)) * 5)
    }

    /// The shoot day's weather in one row, when the forecast reaches that day.
    static func shootDayWeather(_ scenes: [ScoutScene], on date: Date, y: CGFloat) -> CGFloat {
        guard Forecast.allowed, let loc = scenes.lazy.compactMap(place).first,
              let days = Forecast.cached(latitude: loc.latitude, longitude: loc.longitude),
              let d = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
        else { return y }
        // Cloud at golden hour: the evening's hour around sunset.
        let sunDay = SunCalculator.day(containing: date, latitude: loc.latitude, longitude: loc.longitude)
        let goldenHour = LightRead.golden(sunDay).map { Calendar.current.component(.hour, from: $0.lowerBound) }
        let cloud = goldenHour.flatMap { h in d.hourlyCloud.indices.contains(h) ? d.hourlyCloud[h] : nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d MMM"
        var cells: [(label: String, value: String, golden: Bool)] = [
            ("Shoot day", f.string(from: d.date), false),
            ("Sky", d.summary, false),
            ("High / low", "\(Int(d.tempMax.rounded()))° / \(Int(d.tempMin.rounded()))°", false),
            ("Rain", "\(d.rain)%", false),
        ]
        if let cloud { cells.append(("Cloud, golden hour", "\(cloud)%", true)) }
        return grid(cells, y: y)
    }

    /// "Plan for the day": time, place, its shots, the light and the drive on.
    static func drawPlan(_ stops: [PlanStop], firstPage: [UUID: Int], kit: Kit, y top: CGFloat) -> CGFloat {
        guard !stops.isEmpty else { return top }
        var y = top
        caps("Plan for the day · in the order the light comes round", size: 7.5).draw(at: CGPoint(x: pad, y: y))
        y += 14
        let w = page.width - pad * 2
        // A small map per place on the left, then time, place, shots and the light.
        let mapSize = CGSize(width: 112, height: 66)
        let left = pad + mapSize.width + 12
        let cols: [CGFloat] = [left, left + 82, left + (pad + w - left) * 0.52, left + (pad + w - left) * 0.66]
        let one: NSStringDrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        for stop in stops {
            if y + mapSize.height + 12 > page.height - pad - footerH { break }
            line(at: y, color: hair)
            placeMap(stop, kit: kit, in: CGRect(origin: CGPoint(x: pad, y: y + 6), size: mapSize))
            let ty = y + 7
            let golden = stop.why.hasPrefix("golden")
            text("\(Format.time(stop.start))–\(Format.time(stop.end))", font: mono(9.75), color: golden ? sun : ink)
                .draw(at: CGPoint(x: cols[0], y: ty))
            text(stop.scene.name, font: sans(11))
                .draw(with: CGRect(x: cols[1], y: ty - 1, width: cols[2] - cols[1] - 10, height: 14), options: one, context: nil)
            let pageRef = firstPage[stop.scene.id].map { "page \($0)" }
            text(["Scene \(String(format: "%02d", stop.number))", pageRef].compactMap { $0 }.joined(separator: " · "), font: mono(7.5), color: grey)
                .draw(at: CGPoint(x: cols[1], y: ty + 14))
            let numbers = stop.scene.shots.map(\.number)
            let shots = numbers.count <= 6 ? numbers.joined(separator: " ") : "\(numbers[0])–\(numbers[numbers.count - 1]) (\(numbers.count))"
            text(shots, font: mono(8.25))
                .draw(with: CGRect(x: cols[2], y: ty + 1, width: cols[3] - cols[2] - 10, height: 12), options: one, context: nil)
            var read = stop.why
            if let d = stop.driveNext { read += " · \(d) min drive next" }
            text(read, font: mono(8.25), color: grey)
                .draw(with: CGRect(x: cols[3], y: ty + 1, width: pad + w - cols[3], height: 24), options: .usesLineFragmentOrigin, context: nil)
            y += mapSize.height + 12
        }
        line(at: y, color: hair)
        return y + 6
    }

    /// A small real map of one place: where to stand, the way to point, the sun at the
    /// planned time, and north. Left blank with a hairline when the map can't be fetched.
    static func placeMap(_ stop: PlanStop, kit: Kit, in rect: CGRect) {
        let opts = MKMapSnapshotter.Options()
        let center = CLLocationCoordinate2D(latitude: stop.loc.latitude, longitude: stop.loc.longitude)
        // About 250m across.
        let lonSpan = 0.0036 / max(cos(center.latitude * .pi / 180), 0.2)
        opts.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.0036 * Double(rect.height / rect.width), longitudeDelta: lonSpan))
        opts.size = rect.size
        opts.scale = 2
        opts.mapType = .mutedStandard
        opts.pointOfInterestFilter = .excludingAll
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        var result: MKMapSnapshotter.Snapshot?
        let done = DispatchSemaphore(value: 0)
        MKMapSnapshotter(options: opts).start(with: .global(qos: .userInitiated)) { snap, _ in
            result = snap
            done.signal()
        }
        hair.setStroke()
        guard done.wait(timeout: .now() + 8) == .success, let snap = result else {
            UIBezierPath(rect: rect).stroke()
            return
        }
        snap.image.draw(in: rect)
        UIBezierPath(rect: rect).stroke()
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.saveGState()
        UIRectClip(rect)
        let p0 = snap.point(for: center)
        let p = CGPoint(x: rect.minX + p0.x, y: rect.minY + p0.y)
        let r = min(rect.width, rect.height) * 0.42
        // The way to point: a wedge as wide as the lens sees.
        if let b = stop.heading {
            let half = kit.horizontalFOV(focal: stop.lensMM ?? 35) / 2
            let a0 = (b - half - 90) * .pi / 180, a1 = (b + half - 90) * .pi / 180
            let cone = UIBezierPath()
            cone.move(to: p)
            cone.addArc(withCenter: p, radius: r, startAngle: a0, endAngle: a1, clockwise: true)
            cone.close()
            ink.withAlphaComponent(0.1).setFill()
            cone.fill()
            ink.withAlphaComponent(0.5).setStroke()
            cone.lineWidth = 0.5
            cone.stroke()
        }
        // The sun at the planned time, out on the edge, with a dashed line to the spot.
        let sunPos = SunCalculator.position(at: stop.start, latitude: stop.loc.latitude, longitude: stop.loc.longitude)
        let sa = (sunPos.azimuth - 90) * .pi / 180
        let sp = CGPoint(x: p.x + cos(sa) * r * 1.05, y: p.y + sin(sa) * r * 1.05)
        let ray = UIBezierPath()
        ray.move(to: p)
        ray.addLine(to: sp)
        ray.lineWidth = 0.6
        ray.setLineDash([2, 2], count: 2, phase: 0)
        sun.setStroke()
        ray.stroke()
        sun.setFill()
        UIBezierPath(ovalIn: CGRect(x: sp.x - 3.5, y: sp.y - 3.5, width: 7, height: 7)).fill()
        // Where to stand.
        ink.setFill()
        UIBezierPath(ovalIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)).fill()
        // North.
        let n = text("N", font: mono(6))
        n.draw(at: CGPoint(x: rect.maxX - 9, y: rect.minY + 3))
        cg.restoreGState()
    }
}
