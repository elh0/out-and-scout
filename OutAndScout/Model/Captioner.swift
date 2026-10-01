import Foundation

struct CaptionSuggestion: Hashable, Identifiable {
    var text: String
    /// "best match", "also in frame", "alt framing"
    var tag: String
    var id: String { tag }
}

/// Three caption suggestions for a pin, from shot size, what Vision saw, and the light.
/// On-device only for now; an optional online vision model can slot in later.
enum Captioner {
    /// Shot size from the focal length, normalised to a 28mm-wide (ALEXA 35 open gate) sensor
    /// so the same framing gets the same name whatever camera is in the kit.
    static func shotSize(lensMM: Double, sensorWidthMM: Double) -> (size: String, alt: String) {
        let f = lensMM * 28 / max(sensorWidthMM, 1)
        let size: String
        switch f {
        case ..<26: size = "wide"
        case ..<36: size = "medium wide"
        case ..<51: size = "mid"
        case ..<76: size = "close"
        default: size = "tight"
        }
        let alt = f <= 25 ? "establishing" : f <= 50 ? "two-shot" : "detail"
        return (size, alt)
    }

    static func suggestions(
        lensMM: Double,
        sensorWidthMM: Double,
        labels: [String],
        light: LightPhase,
        sunInFrame: Bool
    ) -> [CaptionSuggestion] {
        let (size, alt) = shotSize(lensMM: lensMM, sensorWidthMM: sensorWidthMM)
        let seen = labels.isEmpty ? ["location"] : labels
        let a = seen[0]
        let b = seen.count > 1 ? seen[1] : seen[0]

        let lightBit: String
        switch light {
        case .afterDark, .beforeSunrise: lightBit = ", after dark"
        case .blueHour: lightBit = ", blue hour"
        case .goldenHour: lightBit = sunInFrame ? ", into the sun" : ", golden light"
        default: lightBit = sunInFrame ? ", into the sun" : ""
        }

        return [
            CaptionSuggestion(text: "\(size) · \(a)\(lightBit)", tag: "best match"),
            CaptionSuggestion(text: "\(size) · \(b)", tag: "also in frame"),
            CaptionSuggestion(text: "\(alt) · \(a)", tag: "alt framing"),
        ]
    }

    /// Vision identifiers look like "sky" or "structure_other". Make them readable and drop
    /// the ones that say nothing about a location.
    static func readable(_ identifiers: [String]) -> [String] {
        let skip: Set<String> = ["outdoor", "indoor", "structure", "material", "liquid", "water_body", "consumable"]
        var out: [String] = []
        for id in identifiers where !skip.contains(id) {
            let words = id
                .replacingOccurrences(of: "_other", with: "")
                .replacingOccurrences(of: "_", with: " ")
            if !out.contains(words) { out.append(words) }
        }
        return out
    }
}
