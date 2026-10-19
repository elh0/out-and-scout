import Foundation
import Observation

/// One sky sweep in progress (Elliot, 19 Oct 2026). You follow today's sun path with the
/// phone; each frame's sky edges are placed by the compass and tilt, and once most of the
/// path has been seen the bins become a `Skyline`.
@MainActor
@Observable
final class SkySweep: Identifiable {
    let id = UUID()
    let sceneID: UUID
    let latitude: Double
    let longitude: Double
    /// The stretch of today's sun path to follow, every two minutes: the low sun on the side
    /// the shot faces.
    let path: [SunDay.Sample]
    /// Azimuths are unwrapped from here so the bins stay in order across north.
    private let base: Double

    /// Half-degree bins: sky edge elevations seen there.
    private var seen: [Int: [Double]] = [:]
    /// Bins where the top of the frame wasn't sky: the skyline is at least this high.
    private var above: [Int: Double] = [:]
    /// Bins where the sky ran to the bottom of the frame: the skyline is at most this high.
    private var below: [Int: Double] = [:]
    /// The path's bins, and which of them the camera has looked at.
    private let pathBins: [Int]
    private(set) var covered: Set<Int> = []
    let startedAt = Date()

    var progress: Double { pathBins.isEmpty ? 0 : Double(covered.count) / Double(pathBins.count) }
    var isEnough: Bool { progress >= 0.9 }

    /// The next bit of the path still to look at, for the target dot.
    var target: SunDay.Sample? {
        path.first { !covered.contains(Self.bin(Skyline.unwrap($0.position.azimuth, from: base))) }
    }

    init?(sceneID: UUID, latitude: Double, longitude: Double, bearing: Double, now: Date = Date()) {
        guard let path = Self.pathToSweep(latitude: latitude, longitude: longitude, bearing: bearing, on: now) else { return nil }
        self.sceneID = sceneID
        self.latitude = latitude
        self.longitude = longitude
        self.path = path
        let b = path[0].position.azimuth - 40
        base = b
        pathBins = Array(Set(path.map { Self.bin(Skyline.unwrap($0.position.azimuth, from: b)) })).sorted()
    }

    /// Today's low sun (up to 25° high) within 75° of where the shot faces: the stretch the
    /// sweep follows. The morning or the evening, whichever passes nearest the shot. nil when
    /// the sun never comes round this way today.
    static func pathToSweep(latitude: Double, longitude: Double, bearing: Double, on date: Date) -> [SunDay.Sample]? {
        let day = SunCalculator.day(containing: date, latitude: latitude, longitude: longitude)
        var runs: [[SunDay.Sample]] = []
        var run: [SunDay.Sample] = []
        for s in day.samples {
            let p = s.position
            if p.elevation > -0.5, p.elevation < 25, abs(Bearing.difference(p.azimuth, bearing)) < 75 {
                run.append(s)
            } else if !run.isEmpty {
                runs.append(run)
                run = []
            }
        }
        if !run.isEmpty { runs.append(run) }
        let best = runs.filter { $0.count >= 5 }.min { a, b in
            let da = a.map { abs(Bearing.difference($0.position.azimuth, bearing)) }.min() ?? 180
            let db = b.map { abs(Bearing.difference($0.position.azimuth, bearing)) }.min() ?? 180
            return da < db
        }
        return best
    }

    /// Whether to offer a sweep after a shot: the low sun crosses this way today.
    static func crossesView(latitude: Double, longitude: Double, bearing: Double, on date: Date = Date()) -> Bool {
        guard let path = pathToSweep(latitude: latitude, longitude: longitude, bearing: bearing, on: date) else { return false }
        // Only worth it if the sun is still to come, or there now.
        return (path.last?.time ?? .distantPast) > date.addingTimeInterval(-30 * 60)
    }

    private static func bin(_ unwrapped: Double) -> Int { Int((unwrapped * 2).rounded(.down)) }

    /// One frame's sky edges, placed by where the camera points.
    /// `hfov` is the field of view across the frame's width.
    func ingest(_ cols: SkyColumns, heading: Double, elevation: Double, hfov: Double) {
        let rad = { (d: Double) in d * .pi / 180 }
        let deg = { (r: Double) in r * 180 / .pi }
        let halfW = tan(rad(hfov / 2))
        let halfH = halfW / max(cols.aspect, 0.1)
        let n = cols.edges.count
        let topAlt = elevation + deg(atan(halfH))
        let bottomAlt = elevation - deg(atan(halfH))
        for (i, edge) in cols.edges.enumerated() {
            let x = (Double(i) + 0.5) / Double(n)
            let az = heading + deg(atan((2 * x - 1) * halfW))
            let k = Self.bin(Skyline.unwrap(az, from: base))
            switch edge {
            case nil:
                above[k] = max(above[k] ?? -90, topAlt)
            case let e? where e >= 0.999:
                below[k] = min(below[k] ?? 90, bottomAlt)
            case let e?:
                let alt = elevation + deg(atan((1 - 2 * e) * halfH))
                seen[k, default: []].append(alt)
            }
        }
        // The path counts as looked at where it falls inside the middle of the frame.
        for s in path {
            let dx = Bearing.difference(s.position.azimuth, heading)
            let dy = s.position.elevation - elevation
            guard abs(dx) < hfov * 0.4, abs(dy) < deg(atan(halfH)) * 0.85 else { continue }
            covered.insert(Self.bin(Skyline.unwrap(s.position.azimuth, from: base)))
        }
    }

    /// The line traced so far, for drawing while you sweep.
    var traced: Skyline? { make() }

    /// The finished line: the median of what each bin saw, gaps filled from their
    /// neighbours, then lightly smoothed.
    func make() -> Skyline? {
        let keys = Set(seen.keys).union(above.keys).union(below.keys)
        guard let lo = keys.min(), let hi = keys.max(), hi > lo else { return nil }
        var values: [Double?] = []
        for k in lo...hi {
            if let s = seen[k], !s.isEmpty {
                let sorted = s.sorted()
                var v = sorted[sorted.count / 2]
                if let a = above[k] { v = max(v, a) }
                values.append(v)
            } else if let a = above[k] {
                values.append(a)
            } else if let b = below[k] {
                values.append(b)
            } else {
                values.append(nil)
            }
        }
        // Fill small gaps by straight lines between neighbours.
        var last: Int?
        for i in values.indices where values[i] != nil {
            if let l = last, i - l > 1, let a = values[l], let b = values[i] {
                for j in (l + 1)..<i { values[j] = a + (b - a) * Double(j - l) / Double(i - l) }
            }
            last = i
        }
        let filled = values.map { $0 ?? 0 }
        // A median of three takes out single-column spikes (a bird, a lamppost) and keeps
        // roof edges sharp.
        var smooth = filled
        if filled.count >= 3 {
            for i in 1..<(filled.count - 1) {
                smooth[i] = [filled[i - 1], filled[i], filled[i + 1]].sorted()[1]
            }
        }
        let points = smooth.enumerated().map { i, v in
            Skyline.Point(azimuth: Double(lo + i) / 2 + 0.25, elevation: v)
        }
        return Skyline(points: points, latitude: latitude, longitude: longitude, sweptAt: startedAt)
    }
}
