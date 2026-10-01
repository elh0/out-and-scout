import Foundation

struct SunPosition: Hashable {
    /// Degrees clockwise from true north.
    var azimuth: Double
    /// Degrees above the horizon, corrected for refraction.
    var elevation: Double
}

/// One day of sun for a place, sampled for the timeline and the sun path overlay.
struct SunDay {
    struct Sample: Hashable {
        var time: Date
        var position: SunPosition
    }

    var samples: [Sample]
    var sunrise: Date?
    var sunset: Date?
    /// Spans where the sun is between -4° and 6°.
    var goldenWindows: [ClosedRange<Date>]
    var blueWindows: [ClosedRange<Date>]
}

/// NOAA solar position algorithm (the one behind the NOAA solar calculator spreadsheet).
/// Accurate to well under a degree between 1900 and 2100, which is plenty for framing.
enum SunCalculator {
    static func position(at date: Date, latitude: Double, longitude: Double) -> SunPosition {
        let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545.0) / 36_525.0

        let l0 = normalise(280.46646 + t * (36_000.76983 + t * 0.0003032))
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * m)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * m)) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let decl = asin(sin(rad(eps)) * sin(rad(lambda)))

        let y = pow(tan(rad(eps) / 2), 2)
        let eqTime = 4 * deg(
            y * sin(2 * rad(l0))
                - 2 * e * sin(rad(m))
                + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0))
                - 0.5 * y * y * sin(4 * rad(l0))
                - 1.25 * e * e * sin(2 * rad(m))
        )

        var utcMinutes = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) / 60
        if utcMinutes < 0 { utcMinutes += 1440 }
        var trueSolarTime = (utcMinutes + eqTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if trueSolarTime < 0 { trueSolarTime += 1440 }
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let lat = rad(latitude)
        let cosZenith = sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(rad(hourAngle))
        let zenith = acos(min(1, max(-1, cosZenith)))
        var elevation = 90 - deg(zenith)

        // Atmospheric refraction (Bennett), only meaningful near and above the horizon.
        if elevation > -1 {
            let r = 1.02 / tan(rad(elevation + 10.3 / (elevation + 5.11))) / 60
            elevation += r
        }

        let azimuth = normalise(
            deg(atan2(sin(rad(hourAngle)), cos(rad(hourAngle)) * sin(lat) - tan(decl) * cos(lat))) + 180
        )
        return SunPosition(azimuth: azimuth, elevation: elevation)
    }

    /// Samples the local calendar day containing `date` every `step` seconds.
    static func day(
        containing date: Date,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current,
        step: TimeInterval = 120
    ) -> SunDay {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        var samples: [SunDay.Sample] = []
        var t = start
        while t <= end {
            samples.append(.init(time: t, position: position(at: t, latitude: latitude, longitude: longitude)))
            t = t.addingTimeInterval(step)
        }

        // Sunrise/sunset: upper limb on the horizon, i.e. -0.833° before refraction.
        // We already add refraction, so the crossing is roughly at -0.27°.
        let horizon = -0.27
        var sunrise: Date?
        var sunset: Date?
        for (a, b) in zip(samples, samples.dropFirst()) {
            if a.position.elevation < horizon, b.position.elevation >= horizon, sunrise == nil { sunrise = b.time }
            if a.position.elevation >= horizon, b.position.elevation < horizon { sunset = a.time }
        }

        return SunDay(
            samples: samples,
            sunrise: sunrise,
            sunset: sunset,
            goldenWindows: windows(in: samples) { $0 >= -4 && $0 < 6 },
            blueWindows: windows(in: samples) { $0 >= -6 && $0 < -4 }
        )
    }

    private static func windows(in samples: [SunDay.Sample], where test: (Double) -> Bool) -> [ClosedRange<Date>] {
        var result: [ClosedRange<Date>] = []
        var open: Date?
        for s in samples {
            if test(s.position.elevation) {
                if open == nil { open = s.time }
            } else if let o = open {
                result.append(o...s.time)
                open = nil
            }
        }
        if let o = open, let last = samples.last { result.append(o...last.time) }
        return result
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func normalise(_ d: Double) -> Double {
        let x = d.truncatingRemainder(dividingBy: 360)
        return x < 0 ? x + 360 : x
    }
}
