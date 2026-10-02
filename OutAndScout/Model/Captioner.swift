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
        // People lead when they're in frame: "Mid · two people by the bench".
        var subjects = seen.subjects
        if let people = seen.people {
            subjects = [subjects.first.map { "\(people) by the \($0)" } ?? people] + subjects.dropFirst()
        }
        // A lamp glowing in a dark frame is a practical; Vision rarely names it.
        // It leads the caption, since it's usually why the frame was taken.
        if seen.lightCue == "practical", seen.people == nil {
            subjects.removeAll { $0.contains("lamp") }
            subjects.insert("practical lamp", at: 0)
        }
        if subjects.isEmpty { subjects = [seen.sign.map { "sign: \($0)" } ?? "location"] }
        let a = subjects[0]
        // A readable sign makes a good second subject ("sign: Bakery").
        let b = subjects.count > 1 ? subjects[1] : seen.sign.flatMap { s in a.contains(s) ? nil : "sign: \(s)" }

        let timeBit: String
        switch light {
        case .afterDark, .beforeSunrise: timeBit = ", night"
        case .blueHour: timeBit = ", blue hour"
        case .goldenHour: timeBit = sunInFrame ? ", into the sun" : ", golden hour"
        default: timeBit = sunInFrame ? ", into the sun" : ""
        }
        // What the light is doing in the frame beats the time of day when we can see it.
        let cueBit: String? = switch seen.lightCue ?? "" {
        case "dappled light": ", dappled light"
        case "backlit": ", backlit"
        default: nil
        }
        let lightBit = cueBit ?? timeBit
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
            // Wrong or noisy on real recce stills (benchmark, 2 Oct 2026).
            "screenshot", "document", "portal", "elevator", "raw_glass", "recreation", "sport", "sports_equipment", "ball", "games", "leisure",
        ]
        // Screens come back as three or four synonyms and crowd out the real subjects.
        let screens: Set<String> = ["computer", "computer_monitor", "monitor", "laptop", "computer_screen", "display"]
        let hasLaptop = identifiers.contains("laptop")
        // A keyboard filling the frame should lead, not be folded into "screen". Its parents
        // (machine, consumer_electronics) are skipped, so look past them too.
        if let k = identifiers.firstIndex(of: "computer_keyboard"),
           identifiers.prefix(k).allSatisfy({ screens.contains($0) || skip.contains($0) }) {
            var rest = readable(identifiers.filter { $0 != "computer_keyboard" })
            rest.removeAll { $0 == "keyboard" }
            return ["keyboard"] + rest
        }
        var out: [String] = []
        for id in identifiers where !skip.contains(id) {
            if screens.contains(id) {
                let one = hasLaptop ? "laptop" : "screen"
                if !out.contains(one) { out.append(one) }
                continue
            }
            let words = id
                .replacingOccurrences(of: "_other", with: "")
                .replacingOccurrences(of: "_", with: " ")
            if !out.contains(words) { out.append(words) }
        }
        // Only screen-ish noise ("screenshot", "document")? Then it's a screen.
        if out.isEmpty, identifiers.contains(where: { screens.contains($0) || $0 == "screenshot" || $0 == "document" }) {
            out = ["screen"]
        }
        return out
    }
}
