import Foundation

// Structure: project -> scenes -> numbered shots. Every pin is a shot.

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// "short film", "commercial", "music video"...
    var kind: String
    var scenes: [ScoutScene]
    var createdAt = Date()
}

/// Named `ScoutScene` so it doesn't clash with SwiftUI's `Scene`.
struct ScoutScene: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// e.g. "ext. day · 12 apr"
    var note: String = ""
    var location: ShotLocation?
    var shots: [Shot] = []
}

struct Shot: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Setup number and letter, e.g. "1A". New pins take the next setup number.
    var number: String
    var caption: String
    var lensMM: Double
    var aspect: AspectRatio
    var cameraName: String
    var lensSeries: String
    /// The time of day the shot is planned for (what the sun timeline was set to when pinned).
    var plannedTime: Date
    /// When the pin was actually taken on the recce.
    var capturedAt: Date
    var sunAzimuth: Double
    var sunElevation: Double
    var light: LightPhase
    /// Compass bearing the camera faced, degrees from true north.
    var bearing: Double?
    var location: ShotLocation?
    /// File name of the still in the app's shots folder.
    var photoFile: String?
    /// Shape of the saved still (the sensor mode's shape when it was taken).
    var stillAspect: Double? = nil

    var isGolden: Bool { light == .goldenHour }

    /// "24mm · 19:12 · sun 247°"
    var meta: String {
        "\(Int(lensMM.rounded()))mm · \(Format.time(plannedTime)) · Sun \(Int(sunAzimuth.rounded()))°"
    }
}

struct ShotLocation: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    /// "brick lane, e1"
    var label: String?
    var postcode: String?

    /// "brick lane, e1 · 51.5216°N 0.0717°W"
    var display: String {
        let ns = latitude >= 0 ? "N" : "S"
        let ew = longitude >= 0 ? "E" : "W"
        let coords = String(format: "%.4f°%@ %.4f°%@", abs(latitude), ns, abs(longitude), ew)
        if let label { return "\(label) · \(coords)" }
        return coords
    }

    /// Opens on any phone or computer, so it suits a crew shot list.
    var mapURL: URL? {
        URL(string: String(format: "https://www.google.com/maps/search/?api=1&query=%.6f,%.6f", latitude, longitude))
    }
}

struct AspectRatio: Codable, Hashable, Identifiable {
    var value: Double
    var label: String
    var id: String { label }

    static let scope = AspectRatio(value: 2.39, label: "2.39")
    static let flat = AspectRatio(value: 1.85, label: "1.85")
    static let hd = AspectRatio(value: 16.0 / 9.0, label: "16:9")
    static let vertical = AspectRatio(value: 9.0 / 16.0, label: "9:16")
    /// No frame lines: the whole sensor mode, whatever its shape.
    static let full = AspectRatio(value: 16.0 / 9.0, label: "full")
    static func full(_ value: Double) -> AspectRatio { AspectRatio(value: value, label: "full") }
    /// Shape of stills taken before the viewfinder followed the sensor mode.
    static let viewfinderValue = 16.0 / 9.0

    var isFull: Bool { label == "full" }
    /// What the chip shows: "Full" for the whole frame, otherwise the ratio itself.
    var display: String { isFull ? "Full" : label }

    static let strip: [AspectRatio] = [.scope, .flat, .hd, .vertical]
    /// Offered on the Custom aspect card.
    static let customPresets: [AspectRatio] = [
        AspectRatio(value: 4.0 / 3.0, label: "4:3"),
        AspectRatio(value: 1.66, label: "1.66"),
        AspectRatio(value: 2.0, label: "2:1"),
        AspectRatio(value: 1.0, label: "1:1"),
        AspectRatio(value: 2.76, label: "2.76"),
    ]

    /// Parses "2.2", "2.2:1" or "4:3". Returns nil for nonsense or extreme ratios.
    static func parse(_ text: String) -> AspectRatio? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        let parts = t.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        let value: Double?
        switch parts.count {
        case 1: value = parts[0]
        case 2:
            if let a = parts[0], let b = parts[1], b > 0 { value = a / b } else { value = nil }
        default: value = nil
        }
        guard let v = value, v >= 0.3, v <= 4 else { return nil }
        let label = parts.count == 2 && parts[1] != 1 ? t.replacingOccurrences(of: " ", with: "") : String(format: "%.2f", v)
        return AspectRatio(value: v, label: label)
    }
}

enum LightPhase: String, Codable, CaseIterable {
    case beforeSunrise = "before sunrise"
    case blueHour = "blue hour"
    case goldenHour = "golden hour"
    case morning
    case midday
    case afternoon
    case afterDark = "after dark"

    /// "Golden hour": the stored value stays lowercase, the label reads like a sentence.
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Golden hour: sun between -4° and 6°. Blue hour: -6° to -4°.
    static func from(elevation: Double, localHour: Double) -> LightPhase {
        let morning = localHour < 12
        if elevation < -6 { return morning ? .beforeSunrise : .afterDark }
        if elevation < -4 { return .blueHour }
        if elevation < 6 { return .goldenHour }
        if localHour < 11 { return .morning }
        if localHour < 15 { return .midday }
        return .afternoon
    }
}

enum Format {
    static func time(_ date: Date, in zone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Focal length: "35", "17.5".
    static func mm(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// "247° w"
    static func bearing(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let d = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return "\(Int(d.rounded()) % 360)° \(names[Int((d / 45).rounded()) % 8])"
    }

    /// "12 apr"
    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }

    /// "night shift" -> "night-shift"
    static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let mapped = text.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }
}
