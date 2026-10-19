import Foundation

/// Where the sky starts along the sun's path at one spot, from the sky sweep (Elliot,
/// 19 Oct 2026): the roofs, trees and hills the sun drops behind, as an elevation for every
/// half degree of azimuth the sweep saw. With it the app can say "be here 16:10, the sun
/// clears the roof 16:20" instead of only sunrise and sunset.
struct Skyline: Codable, Hashable {
    struct Point: Codable, Hashable {
        /// Degrees from true north. Runs on past 360 when a sweep crosses north, so the
        /// points stay in order.
        var azimuth: Double
        /// Degrees above the horizon where the sky starts.
        var elevation: Double
    }

    /// Sorted by azimuth.
    var points: [Point]
    /// Where it was swept, so the sun can be worked out for any shoot day.
    var latitude: Double
    var longitude: Double
    var sweptAt: Date
    /// True once the line has been dragged by hand.
    var edited = false

    var first: Double? { points.first?.azimuth }
    var last: Double? { points.last?.azimuth }

    /// The skyline's height at an azimuth, or nil outside what the sweep saw.
    func elevation(at azimuth: Double) -> Double? {
        guard let lo = first, let hi = last, points.count > 1 else { return points.first?.elevation }
        let a = Self.unwrap(azimuth, from: lo)
        guard a <= hi else { return nil }
        // Binary search for the pair either side.
        var l = 0, r = points.count - 1
        while r - l > 1 {
            let m = (l + r) / 2
            if points[m].azimuth <= a { l = m } else { r = m }
        }
        let p = points[l], q = points[r]
        let span = q.azimuth - p.azimuth
        guard span > 0 else { return p.elevation }
        return p.elevation + (q.elevation - p.elevation) * (a - p.azimuth) / span
    }

    /// An azimuth moved into [base, base + 360).
    static func unwrap(_ azimuth: Double, from base: Double) -> Double {
        var d = (azimuth - base).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return base + d
    }
}

/// What the skyline means for the sun on a given day at that spot.
struct SkyRead {
    /// Spans with direct sun on the spot: the sun is up and above the skyline.
    var sunOn: [ClosedRange<Date>]
    /// When the sun comes out from behind something (not sunrise).
    var clears: Date?
    /// When the sun drops behind something before it sets.
    var hides: Date?
    /// When the sun first goes behind something on its way to `clears`, if it does.
    var hidesBefore: Date?
    var sunset: Date?
    var goldenStart: Date?
    /// The sun stays behind something the whole way along the part that was swept.
    var shadedThroughout: Bool

    /// Ten minutes before the sun clears: time to be set up.
    var beHere: Date? { clears?.addingTimeInterval(-10 * 60) }

    /// "Sun clears the roof 16:20 · behind it 17:28"
    var summary: String {
        switch (clears, hides) {
        case let (c?, h?) where h > c: return "Sun clears the roof \(Format.time(c)) · behind it \(Format.time(h))"
        case let (c?, _): return "Sun clears the roof \(Format.time(c))"
        case let (nil, h?): return "Sun behind the roof from \(Format.time(h))"
        default:
            if shadedThroughout { return "In shade along the sun's path" }
            return "Nothing in the way" + (sunset.map { " · sun till \(Format.time($0))" } ?? "")
        }
    }

    /// The day at the spot, every minute.
    static func read(_ sky: Skyline, on date: Date) -> SkyRead {
        let day = SunCalculator.day(containing: date, latitude: sky.latitude, longitude: sky.longitude, step: 60)
        var spans: [ClosedRange<Date>] = []
        var open: Date?
        var clears: Date?, hides: Date?, hidesBefore: Date?
        var prevUp = false, prevLit = false
        var sawSwept = false, sawLit = false
        for s in day.samples {
            let up = s.position.elevation > -0.3
            let wall = sky.elevation(at: s.position.azimuth)
            if up, wall != nil { sawSwept = true }
            let lit = up && s.position.elevation > (wall ?? -90)
            if lit, wall != nil { sawLit = true }
            if lit && !prevLit {
                open = s.time
                // Up a moment ago but behind something: it has just cleared it.
                if prevUp, clears == nil { clears = s.time }
            }
            if !lit && prevLit {
                if let o = open { spans.append(o...s.time) }
                open = nil
                // Still up, so it went behind something rather than setting.
                if up {
                    if clears == nil, hidesBefore == nil { hidesBefore = s.time }
                    hides = s.time
                }
            }
            prevUp = up
            prevLit = lit
        }
        if let o = open, let last = day.samples.last { spans.append(o...last.time) }
        // `hides` keeps the last time it went behind something; one before it cleared isn't it.
        if let h = hides, let c = clears, h < c { hides = nil }
        return SkyRead(
            sunOn: spans, clears: clears, hides: hides, hidesBefore: hidesBefore,
            sunset: day.sunset, goldenStart: LightRead.golden(day)?.lowerBound,
            shadedThroughout: sawSwept && !sawLit
        )
    }
}
