import Foundation

/// The moon for after sunset (Elliot, 6 Oct 2026): where it is, and how full.
struct MoonInfo {
    var position: SunPosition
    /// 0 (new) to 1 (full).
    var illumination: Double
    var waxing: Bool

    /// "Waxing gibbous"
    var phaseName: String {
        let i = illumination
        if i < 0.03 { return "New moon" }
        if i > 0.97 { return "Full moon" }
        let grow = waxing ? "Waxing" : "Waning"
        if i < 0.47 { return "\(grow) crescent" }
        if i <= 0.53 { return waxing ? "First quarter" : "Last quarter" }
        return "\(grow) gibbous"
    }

    /// "Waxing gibbous · 78% lit"
    var summary: String { "\(phaseName) · \(Int((illumination * 100).rounded()))% lit" }
}

/// Paul Schlyter's low-precision moon (the main perturbations), good to well under a degree:
/// plenty to say where to look and how full it is.
enum MoonCalculator {
    static func info(at date: Date, latitude: Double, longitude: Double) -> MoonInfo {
        let d = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_543.5

        // Sun
        let ws = 282.9404 + 4.70935e-5 * d
        let ms = norm(356.0470 + 0.9856002585 * d)
        let ls = norm(ws + ms)
        let sunLon = norm(ls + 1.915 * sinD(ms) + 0.020 * sinD(2 * ms))

        // Moon orbit
        let n = norm(125.1228 - 0.0529538083 * d)
        let i = 5.1454
        let w = norm(318.0634 + 0.1643573223 * d)
        let a = 60.2666
        let e = 0.054900
        let m = norm(115.3654 + 13.0649929509 * d)

        var ecc = m + e * (180 / .pi) * sinD(m) * (1 + e * cosD(m))
        for _ in 0..<3 {
            ecc -= (ecc - e * (180 / .pi) * sinD(ecc) - m) / (1 - e * cosD(ecc))
        }
        let xv = a * (cosD(ecc) - e)
        let yv = a * (1 - e * e).squareRoot() * sinD(ecc)
        let v = atan2D(yv, xv)
        var r = (xv * xv + yv * yv).squareRoot()

        let xh = r * (cosD(n) * cosD(v + w) - sinD(n) * sinD(v + w) * cosD(i))
        let yh = r * (sinD(n) * cosD(v + w) + cosD(n) * sinD(v + w) * cosD(i))
        let zh = r * sinD(v + w) * sinD(i)
        var lon = atan2D(yh, xh)
        var lat = atan2D(zh, (xh * xh + yh * yh).squareRoot())

        let lm = n + w + m
        let dd = lm - ls
        let f = lm - n
        lon += -1.274 * sinD(m - 2 * dd) + 0.658 * sinD(2 * dd) - 0.186 * sinD(ms)
            - 0.059 * sinD(2 * m - 2 * dd) - 0.057 * sinD(m - 2 * dd + ms) + 0.053 * sinD(m + 2 * dd)
            + 0.046 * sinD(2 * dd - ms) + 0.041 * sinD(m - ms) - 0.035 * sinD(dd)
            - 0.031 * sinD(m + ms) - 0.015 * sinD(2 * f - 2 * dd) + 0.011 * sinD(m - 4 * dd)
        lat += -0.173 * sinD(f - 2 * dd) - 0.055 * sinD(m - f - 2 * dd) - 0.046 * sinD(m + f - 2 * dd)
            + 0.033 * sinD(f + 2 * dd) + 0.017 * sinD(2 * m + f)
        r += -0.58 * cosD(m - 2 * dd) - 0.46 * cosD(2 * dd)
        lon = norm(lon)

        // Ecliptic to equatorial.
        let ecl = 23.4393 - 3.563e-7 * d
        let xe = cosD(lat) * cosD(lon), ye = cosD(lat) * sinD(lon), ze = sinD(lat)
        let xq = xe, yq = ye * cosD(ecl) - ze * sinD(ecl), zq = ye * sinD(ecl) + ze * cosD(ecl)
        let ra = atan2D(yq, xq)
        let dec = atan2D(zq, (xq * xq + yq * yq).squareRoot())

        // Local hour angle, then altitude and azimuth.
        var ut = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) / 3600
        if ut < 0 { ut += 24 }
        let lst = norm(ls + 180 + ut * 15 + longitude)
        let ha = lst - ra
        let x = cosD(ha) * cosD(dec), y = sinD(ha) * cosD(dec), z = sinD(dec)
        let xhor = x * sinD(latitude) - z * cosD(latitude)
        let zhor = x * cosD(latitude) + z * sinD(latitude)
        let az = norm(atan2D(y, xhor) + 180)
        var alt = atan2D(zhor, (xhor * xhor + y * y).squareRoot())
        // Seen from the ground, not the earth's centre.
        alt -= asin(1 / r) * 180 / .pi * cosD(alt)

        let elong = acos(min(1, max(-1, cosD(sunLon - lon) * cosD(lat)))) * 180 / .pi
        return MoonInfo(
            position: SunPosition(azimuth: az, elevation: alt),
            illumination: (1 - cosD(elong)) / 2,
            waxing: norm(lon - sunLon) < 180
        )
    }

    private static func sinD(_ x: Double) -> Double { sin(x * .pi / 180) }
    private static func cosD(_ x: Double) -> Double { cos(x * .pi / 180) }
    private static func atan2D(_ y: Double, _ x: Double) -> Double { atan2(y, x) * 180 / .pi }
    private static func norm(_ x: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
