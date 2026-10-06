import Foundation

/// How the sun falls on a shot, from the way the camera faces (Elliot's export, 6 Oct 2026).
/// rel = sun azimuth - camera heading, -180...180; positive means the sun is camera right.
enum LightClass: Int, CaseIterable {
    case backlit, threeQuarterBack, side, threeQuarterFront, front

    static func of(rel: Double) -> LightClass {
        switch abs(rel) {
        case ...30: return .backlit
        case ...75: return .threeQuarterBack
        case ...105: return .side
        case ...150: return .threeQuarterFront
        default: return .front
        }
    }

    /// "Three-quarter back"
    var name: String {
        switch self {
        case .backlit: return "Backlit"
        case .threeQuarterBack: return "Three-quarter back"
        case .side: return "Side lit"
        case .threeQuarterFront: return "Three-quarter front"
        case .front: return "Front lit"
        }
    }

    /// "¾ back", for running text.
    var short: String {
        switch self {
        case .backlit: return "backlit"
        case .threeQuarterBack: return "¾ back"
        case .side: return "side lit"
        case .threeQuarterFront: return "¾ front"
        case .front: return "front lit"
        }
    }

    /// "¾B", for the day strip.
    var letter: String {
        switch self {
        case .backlit: return "B"
        case .threeQuarterBack: return "¾B"
        case .side: return "S"
        case .threeQuarterFront: return "¾F"
        case .front: return "F"
        }
    }
}

enum LightRead {
    struct Window {
        var start: Date
        var end: Date
        var light: LightClass
        var minutes: Double { end.timeIntervalSince(start) / 60 }
    }

    struct Best {
        var start: Date
        var end: Date
        var light: LightClass
        /// "golden hour, ¾ back" or "backlit, sun 6° up"
        var why: String
    }

    static func rel(sunAzimuth: Double, heading: Double) -> Double {
        Bearing.difference(sunAzimuth, heading)
    }

    /// "Sun 40° off the lens axis · sun camera right"
    static func offAxis(rel: Double) -> String {
        let a = abs(rel)
        let side = a < 8 || a > 172 ? "" : (rel > 0 ? " · sun camera right" : " · sun camera left")
        return "Sun \(Int(a.rounded()))° off the lens axis\(side)"
    }

    /// The day from sunrise to sunset in the sun calculator's 2 min steps, each step
    /// classified for this heading, merged into windows.
    static func windows(day: SunDay, heading: Double) -> [Window] {
        guard let rise = day.sunrise, let set = day.sunset else { return [] }
        var out: [Window] = []
        for s in day.samples where s.time >= rise && s.time <= set {
            let k = LightClass.of(rel: rel(sunAzimuth: s.position.azimuth, heading: heading))
            if let last = out.last, last.light == k {
                out[out.count - 1].end = s.time
            } else {
                out.append(Window(start: s.time, end: s.time, light: k))
            }
        }
        return out
    }

    /// The evening golden hour (the one a crew plans around).
    static func golden(_ day: SunDay) -> ClosedRange<Date>? { day.goldenWindows.last }

    static func light(at time: Date, day: SunDay, heading: Double) -> LightClass? {
        guard let s = sample(at: time, day) else { return nil }
        return LightClass.of(rel: rel(sunAzimuth: s.position.azimuth, heading: heading))
    }

    static func elevation(at time: Date, _ day: SunDay) -> Double {
        sample(at: time, day)?.position.elevation ?? 0
    }

    private static func sample(at time: Date, _ day: SunDay) -> SunDay.Sample? {
        day.samples.min { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) }
    }

    /// Golden hour when it lands behind or beside the lens; else the first backlit window
    /// (then three-quarter back) of 20 min or more once the sun is 6° up, capped at an hour;
    /// else golden hour anyway.
    static func best(day: SunDay, heading: Double) -> Best? {
        let g = golden(day)
        let gLight = g.flatMap { light(at: $0.lowerBound.addingTimeInterval($0.upperBound.timeIntervalSince($0.lowerBound) / 2), day: day, heading: heading) }
        if let g, let gLight, gLight.rawValue <= LightClass.side.rawValue {
            return Best(start: g.lowerBound, end: g.upperBound, light: gLight, why: "golden hour, \(gLight.short)")
        }
        let all = windows(day: day, heading: heading)
        for k in [LightClass.backlit, .threeQuarterBack] {
            for w in all where w.light == k && w.minutes >= 20 {
                var start = w.start
                while start < w.end && elevation(at: start, day) < 6 { start = start.addingTimeInterval(120) }
                guard w.end.timeIntervalSince(start) >= 20 * 60 else { continue }
                let end = min(w.end, start.addingTimeInterval(3600))
                return Best(start: start, end: end, light: k,
                            why: "\(k.short), sun \(Int(elevation(at: start, day).rounded()))° up")
            }
        }
        if let g, let gLight {
            return Best(start: g.lowerBound, end: g.upperBound, light: gLight, why: "golden hour, \(gLight.short)")
        }
        return nil
    }

    /// "07:40–08:52, 16:10–16:40", windows of 10 min or more, or nil when there are none.
    static func spans(_ k: LightClass, day: SunDay, heading: Double) -> String? {
        let w = windows(day: day, heading: heading).filter { $0.light == k && $0.minutes >= 10 }
        guard !w.isEmpty else { return nil }
        return w.map { "\(Format.time($0.start))–\(Format.time($0.end))" }.joined(separator: ", ")
    }
}
