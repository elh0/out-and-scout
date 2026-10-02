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
        seen: VisionResult,
        light: LightPhase,
        sunInFrame: Bool
    ) -> [CaptionSuggestion] {
        let (size, alt) = shotSize(lensMM: lensMM, sensorWidthMM: sensorWidthMM)
        let subjects = seen.subjects.isEmpty ? ["location"] : seen.subjects
        let a = subjects[0]
        let b = subjects.count > 1 ? subjects[1] : nil

        let lightBit: String
        switch light {
        case .afterDark, .beforeSunrise: lightBit = ", night"
        case .blueHour: lightBit = ", blue hour"
        case .goldenHour: lightBit = sunInFrame ? ", into the sun" : ", golden hour"
        default: lightBit = sunInFrame ? ", into the sun" : ""
        }
        // "int. wide · lamp, night", like a slugline.
        let slug = seen.setting.map { "\($0). " } ?? ""

        // Sentence case, so "Wide · lamp, night" or "INT. Wide · lamp, night".
        let cap = { (t: String) in t.prefix(1).uppercased() + t.dropFirst() }
        return [
            CaptionSuggestion(text: "\(slug)\(cap(size)) · \(a)\(lightBit)", tag: "Best match"),
            CaptionSuggestion(text: cap(b.map { "\(size) · \(a) and \($0)" } ?? "\(size) · \(a)"), tag: "Also in frame"),
            CaptionSuggestion(text: "\(slug)\(cap(alt)) · \(b ?? a)", tag: "Alt framing"),
        ]
    }

    /// Vision identifiers look like "sky" or "structure_other". Make them readable and drop
    /// the broad parent labels that say nothing about the shot ("machine", "structure").
    static func readable(_ identifiers: [String]) -> [String] {
        // Checked against Vision's taxonomy and real stills from the app (1 Oct 2026).
        let skip: Set<String> = [
            "outdoor", "interior_room", "structure", "material", "liquid", "water_body", "consumable",
            "machine", "consumer_electronics", "container", "conveyance", "furniture", "textile",
            "people", "adult", "wood_processed", "wood_natural", "art", "decoration",
            "office_supplies", "housewares", "tool", "cord", "light", "sky",
        ]
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
