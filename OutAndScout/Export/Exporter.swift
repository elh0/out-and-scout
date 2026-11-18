import PDFKit
import UIKit

/// Builds the shot list files. PDF: a cover plus a page per scene. CSV: a row per shot.
enum Exporter {
    enum FileFormat: String, CaseIterable {
        case pdf, csv
    }

    /// The three PDFs (Elliot, 6 Oct 2026): shot cards, the ruled list, or just the frames.
    enum Tier: String, CaseIterable {
        case detailed, summary, photos
        var label: String {
            switch self {
            case .detailed: return "Detailed"
            case .summary: return "Summary"
            case .photos: return "Photos only"
            }
        }
    }

    struct Options {
        var frames = true
        var sunTimes = true
        /// Each shot's notes on the Detailed cards and Summary rows.
        var notes = true
        var tier = Tier.detailed
        /// The kit the cards' camera, mode, sensor and resolution come from.
        var kit = Kit.default
        /// Free: "Scouted with Out & Scout · outandscout.com" along the foot of every page.
        /// Pro turns it off.
        var credit = true
    }

    /// shot-list_night-shift_all-scenes.pdf, shot-list_night-shift_brick-lane.csv
    static func filename(project: Project, scene: ScoutScene?, format: FileFormat) -> String {
        let scope = scene.map { Format.slug($0.name) } ?? "all-scenes"
        return "shot-list_\(Format.slug(project.name))_\(scope).\(format.rawValue)"
    }

    /// Turns a typed name into a safe file name (no slashes or colons), without the extension.
    static func cleanName(_ name: String) -> String {
        let safe = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/:\\"))
            .joined(separator: "-")
        return String(safe.prefix(120))
    }

    /// Writes the file to a temporary folder and returns its URL, ready to share.
    /// `name` overrides the default file name (without extension).
    static func export(project: Project, scene: ScoutScene?, format: FileFormat, options: Options, name: String? = nil) throws -> URL {
        let scenes = scene.map { [$0] } ?? project.scenes
        let url = fileURL(project: project, scene: scene, format: format, name: name)
        switch format {
        case .csv:
            // The BOM tells Excel it's UTF-8, so "°" and "·" survive.
            try ("\u{FEFF}" + csv(project: project, scenes: scenes, options: options)).data(using: .utf8)!.write(to: url, options: .atomic)
        case .pdf:
            try pdf(project: project, scenes: scenes, options: options).write(to: url, options: .atomic)
        }
        return url
    }

    /// Where an export is written: the typed name if there is one, else the default.
    static func fileURL(project: Project, scene: ScoutScene?, format: FileFormat, name: String? = nil) -> URL {
        let file = name.map { cleanName($0) }.flatMap { $0.isEmpty ? nil : "\($0).\(format.rawValue)" }
            ?? filename(project: project, scene: scene, format: format)
        return FileManager.default.temporaryDirectory.appendingPathComponent(file)
    }

    // MARK: CSV

    static func csv(project: Project, scenes: [ScoutScene], options: Options) -> String {
        var header = ["project", "scene", "shot", "caption", "lens_mm", "aspect", "camera", "lens_set", "time", "light", "sun_side"]
        if options.sunTimes { header += ["sun_azimuth", "sun_elevation"] }
        header += ["bearing", "location", "postcode", "latitude", "longitude", "map_link", "pinned_at"]

        let iso = ISO8601DateFormatter()
        var lines = [header.joined(separator: ",")]
        for scene in scenes {
            for shot in scene.shots {
                var row: [String] = [
                    project.name, scene.name, shot.number, shot.caption,
                    Format.mm(shot.lensMM), shot.aspect.label, shot.cameraName, shot.lensSeries,
                    Format.time(shot.plannedTime), shot.light.label, shot.sunSide ?? "",
                ]
                if options.sunTimes {
                    row += [String(format: "%.1f", shot.sunAzimuth), String(format: "%.1f", shot.sunElevation)]
                }
                row += [
                    shot.bearing.map { String(format: "%.0f", $0) } ?? "",
                    shot.location?.label ?? "",
                    shot.location?.postcode ?? "",
                    shot.location.map { String(format: "%.6f", $0.latitude) } ?? "",
                    shot.location.map { String(format: "%.6f", $0.longitude) } ?? "",
                    shot.location?.mapURL?.absoluteString ?? "",
                    iso.string(from: shot.capturedAt),
                ]
                lines.append(row.map(escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: PDF

    static let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points

    // 1.1 Paper: ink, grey, line and the one orange.
    static let ink = UIColor(hex: 0x151513)
    static let graphite = UIColor(hex: 0x6E6B64)
    static let rule = UIColor(hex: 0xCFCBC2)
    static let sun = UIColor(hex: 0xE2531F)
    /// Geist (not Mono), only for the big numbers.
    static func big(_ size: CGFloat) -> UIFont {
        UIFont(name: "Geist-Medium", size: size) ?? .systemFont(ofSize: size, weight: .medium)
    }

    // Geist Mono for every word in the PDF too, as in the app (Elliot, 6 Oct 2026).
    static func sans(_ size: CGFloat, medium: Bool = false) -> UIFont {
        UIFont(name: medium ? "GeistMono-Medium" : "GeistMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: medium ? .medium : .regular)
    }

    static func mono(_ size: CGFloat) -> UIFont {
        UIFont(name: "GeistMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // Layout follows the "08 PDF · cover" and "09 PDF · scene page" boards (794px wide),
    // scaled to A4 points (× 0.75).
    static let pad: CGFloat = 42
    static let dark = UIColor(red: 0x33 / 255, green: 0x33 / 255, blue: 0x2F / 255, alpha: 1)
    static let footerH: CGFloat = 20

    /// Shots per scene page, from the row height.
    static func rowHeight(_ options: Options) -> CGFloat { options.frames ? 70 : 40 }
    static func rowsPerPage(_ options: Options) -> Int {
        // Room under the scene header and sun grid, above the footer.
        // The sun path chart takes another 140 when sun times are on.
        let avail = page.height - pad * 2 - 150 - (options.sunTimes ? 136 : 0) - footerH
        return max(1, Int(avail / rowHeight(options)))
    }
    static func pages(for scene: ScoutScene, _ options: Options) -> Int {
        max(1, Int(ceil(Double(scene.shots.count) / Double(rowsPerPage(options)))))
    }

    static func pdf(project: Project, scenes: [ScoutScene], options: Options) -> Data {
        let data = pages(project: project, scenes: scenes, options: options)
        return options.credit ? withCredit(data) : data
    }

    static let creditLine = "Scouted with Out & Scout · outandscout.com"

    /// Redraws each page and adds the free credit line at the very foot, centred, under the
    /// page footer. Vector in, vector out.
    static func withCredit(_ data: Data) -> Data {
        guard let doc = PDFDocument(data: data), doc.pageCount > 0 else { return data }
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            for i in 0..<doc.pageCount {
                guard let pdfPage = doc.page(at: i) else { continue }
                autoreleasepool {
                    let bounds = pdfPage.bounds(for: .mediaBox)
                    ctx.beginPage(withBounds: bounds, pageInfo: [:])
                    let cg = ctx.cgContext
                    cg.saveGState()
                    cg.translateBy(x: 0, y: bounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    pdfPage.draw(with: .mediaBox, to: cg)
                    cg.restoreGState()
                    let credit = text(creditLine, font: mono(7.5), color: graphite)
                    let size = credit.size()
                    credit.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: bounds.height - 18))
                }
            }
        }
    }

    private static func pages(project: Project, scenes: [ScoutScene], options: Options) -> Data {
        switch options.tier {
        case .detailed: return detailedPDF(project: project, scenes: scenes, options: options)
        case .photos: return photosPDF(project: project, scenes: scenes)
        case .summary: break
        }
        let total = 1 + scenes.reduce(0) { $0 + pages(for: $1, options) }
        // Each scene's first page number, for the cover's table.
        var firstPage: [UUID: Int] = [:]
        var n = 2
        for scene in scenes {
            firstPage[scene.id] = n
            n += pages(for: scene, options)
        }
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            drawCover(ctx, project: project, scenes: scenes, firstPage: firstPage, total: total, options: options)
            var pageNo = 2
            for (i, scene) in scenes.enumerated() {
                drawScene(ctx, project: project, scene: scene, index: i + 1, startPage: &pageNo, total: total, options: options)
            }
        }
    }

    static func text(_ s: String, font: UIFont, color: UIColor = ink, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    static func line(at y: CGFloat, color: UIColor = rule, weight: CGFloat = 0.75) {
        color.setFill()
        UIRectFill(CGRect(x: pad, y: y, width: page.width - pad * 2, height: weight))
    }

    static func dot(at p: CGPoint, golden: Bool, size: CGFloat = 5) {
        let r = CGRect(x: p.x, y: p.y, width: size, height: size)
        if golden {
            sun.setFill()
            UIBezierPath(ovalIn: r).fill()
        } else {
            graphite.setStroke()
            let path = UIBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    static func footer(left: String, page pageNo: Int, of total: Int) {
        let y = page.height - pad - 9
        text(left, font: mono(8.5), color: graphite).draw(at: CGPoint(x: pad, y: y))
        let right = text("Page \(pageNo) of \(total)", font: mono(8.5), color: graphite)
        right.draw(at: CGPoint(x: page.width - pad - right.size().width, y: y))
    }

    /// Four label/value cells between an ink rule and a light rule.
    static func grid(_ cells: [(label: String, value: String, golden: Bool)], y: CGFloat) -> CGFloat {
        line(at: y, color: ink)
        let colW = (page.width - pad * 2) / CGFloat(cells.count)
        for (i, c) in cells.enumerated() {
            let x = pad + CGFloat(i) * colW
            text(c.label, font: mono(8.5), color: graphite).draw(at: CGPoint(x: x, y: y + 9))
            var vx = x
            if c.golden {
                dot(at: CGPoint(x: x, y: y + 27), golden: true)
                vx += 10
            }
            text(c.value, font: mono(11)).draw(at: CGPoint(x: vx, y: y + 22))
        }
        line(at: y + 46)
        return y + 46
    }

    /// The day's sun path across the compass (N E S W along the bottom, height up the side),
    /// golden hour in orange, every other hour marked, and a tick for the way each shot faced.
    /// With `suns`, each shot also gets an orange dot where the sun was for it (the Detailed PDF).
    static func sunPathChart(scene: ScoutScene, at loc: ShotLocation, on date: Date, y top: CGFloat, suns: Bool = false) -> CGFloat {
        let day = SunCalculator.day(containing: date, latitude: loc.latitude, longitude: loc.longitude)
        let h: CGFloat = 96
        let w = page.width - pad * 2
        let maxEl = max(10, (day.samples.map(\.position.elevation).max() ?? 10) + 4)
        // Room under the horizon for the shot ticks and their numbers.
        let minEl = -14.0
        let plot = CGRect(x: pad, y: top + 14, width: w, height: h)
        func point(_ az: Double, _ el: Double) -> CGPoint {
            CGPoint(x: plot.minX + plot.width * az / 360,
                    y: plot.maxY - plot.height * (el - minEl) / (maxEl - minEl))
        }

        text("Sun path", font: mono(8.5), color: graphite).draw(at: CGPoint(x: pad, y: top))

        // Horizon and compass points.
        let horizon = point(0, 0).y
        rule.setFill()
        UIRectFill(CGRect(x: plot.minX, y: horizon, width: plot.width, height: 0.75))
        for (az, label) in [(0.0, "N"), (90.0, "E"), (180.0, "S"), (270.0, "W"), (360.0, "N")] {
            let x = point(az, 0).x
            UIRectFill(CGRect(x: x - 0.375, y: plot.minY, width: 0.75, height: plot.height))
            let t = text(label, font: mono(8), color: graphite)
            t.draw(at: CGPoint(x: min(max(x - t.size().width / 2, plot.minX), plot.maxX - t.size().width), y: plot.maxY + 3))
        }

        // The path, split where it wraps past north; golden stretches drawn over it.
        let path = UIBezierPath(), golden = UIBezierPath()
        var last: Double?, lastGolden = false
        let calendar = Calendar.current
        for s in day.samples where s.position.elevation > -6 {
            let p = point(s.position.azimuth, s.position.elevation)
            let wrapped = last.map { abs($0 - s.position.azimuth) > 180 } ?? true
            if wrapped { path.move(to: p) } else { path.addLine(to: p) }
            let isGolden = s.position.elevation >= -4 && s.position.elevation < 6
            if isGolden && lastGolden && !wrapped { golden.addLine(to: p) } else if isGolden { golden.move(to: p) }
            last = s.position.azimuth
            lastGolden = isGolden
            let c = calendar.dateComponents([.hour, .minute], from: s.time)
            if c.minute == 0, (c.hour ?? 1) % 2 == 0, s.position.elevation > 0 {
                ink.setFill()
                UIBezierPath(ovalIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)).fill()
                let t = text(String(format: "%02d", c.hour ?? 0), font: mono(7), color: graphite)
                t.draw(at: CGPoint(x: p.x - t.size().width / 2, y: p.y - 11))
            }
        }
        graphite.setStroke()
        path.lineWidth = 1
        path.stroke()
        sun.setStroke()
        golden.lineWidth = 2
        golden.lineCapStyle = .round
        golden.stroke()

        // Which way each shot faced.
        var placed: [CGFloat] = []
        for shot in scene.shots {
            guard let b = shot.bearing else { continue }
            let x = point(b, 0).x
            ink.setFill()
            UIRectFill(CGRect(x: x - 0.5, y: horizon - 6, width: 1, height: 12))
            // Stagger labels that would overlap.
            let row = placed.filter { abs($0 - x) < 16 }.count
            placed.append(x)
            let t = text(shot.number, font: mono(7))
            t.draw(at: CGPoint(x: x - t.size().width / 2, y: horizon + 7 + CGFloat(row) * 9))
        }

        // Where the sun was for each shot.
        if suns {
            var labelled: [CGPoint] = []
            for shot in scene.shots where shot.sunElevation > minEl {
                let p = point(shot.sunAzimuth, shot.sunElevation)
                sun.setFill()
                UIBezierPath(ovalIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)).fill()
                let row = labelled.filter { abs($0.x - p.x) < 16 && abs($0.y - p.y) < 10 }.count
                labelled.append(p)
                let t = text(shot.number, font: mono(7), color: sun)
                t.draw(at: CGPoint(x: p.x + 5, y: p.y - 13 - CGFloat(row) * 9))
            }
        }
        return plot.maxY + 14
    }

    /// Sunrise, the evening golden and blue hours, and sunset for a place on the recce day.
    static func sunTimes(at loc: ShotLocation?, on date: Date) -> (rise: String, golden: String, set: String, blue: String) {
        guard let loc else { return ("–", "–", "–", "–") }
        let day = SunCalculator.day(containing: date, latitude: loc.latitude, longitude: loc.longitude)
        let span = { (r: ClosedRange<Date>?) in r.map { "\(Format.time($0.lowerBound)) – \(Format.time($0.upperBound))" } ?? "–" }
        return (day.sunrise.map { Format.time($0) } ?? "–", span(day.goldenWindows.last),
                day.sunset.map { Format.time($0) } ?? "–", span(day.blueWindows.last))
    }

    static func place(of scene: ScoutScene) -> ShotLocation? {
        scene.location ?? scene.shots.first(where: { $0.location != nil })?.location
    }

    static func recceDate(_ scenes: [ScoutScene]) -> Date {
        scenes.flatMap(\.shots).map(\.capturedAt).min() ?? Date()
    }

    static func coords(_ loc: ShotLocation) -> String {
        String(format: "%.4f°%@ %.4f°%@", abs(loc.latitude), loc.latitude >= 0 ? "N" : "S",
               abs(loc.longitude), loc.longitude >= 0 ? "E" : "W")
    }

    static func lightWord(_ shot: Shot) -> String {
        shot.light == .goldenHour ? "Golden" : shot.light.label
    }

    static func drawCover(_ ctx: UIGraphicsPDFRendererContext, project: Project, scenes: [ScoutScene],
                                  firstPage: [UUID: Int], total: Int, options: Options) {
        ctx.beginPage()
        let w = page.width - pad * 2
        let date = recceDate(scenes)
        wordmark(at: CGPoint(x: pad, y: pad), size: 12)
        let scope = text("Shot List · \(scenes.count == 1 ? scenes[0].name : "All scenes")", font: mono(8.5), color: graphite)
        scope.draw(at: CGPoint(x: page.width - pad - scope.size().width, y: pad + 2))

        if options.tier != .detailed {
            summaryCover(ctx, project: project, scenes: scenes, firstPage: firstPage, total: total, options: options)
            return
        }

        var y = pad + 50
        let kicker = [project.kind, "recce \(Format.shortDate(date)) \(Calendar.current.component(.year, from: date))"]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        text(kicker, font: mono(9), color: graphite).draw(at: CGPoint(x: pad, y: y))
        y += 16
        let title = text(project.name, font: sans(66, medium: true), kern: -3.3)
        let titleRect = title.boundingRect(with: CGSize(width: w, height: 200), options: .usesLineFragmentOrigin, context: nil)
        title.draw(with: CGRect(x: pad, y: y, width: w, height: 200), options: .usesLineFragmentOrigin, context: nil)
        y += ceil(titleRect.height) + 6
        let shotCount = scenes.reduce(0) { $0 + $1.shots.count }
        var kitLine = ["\(scenes.count) scene\(scenes.count == 1 ? "" : "s")", ShotListView.shots(shotCount)]
        if let first = scenes.flatMap(\.shots).first {
            kitLine.append("Camera \(first.cameraName)")
            kitLine.append("Lenses \(first.lensSeries)")
        }
        text(kitLine.joined(separator: " · "), font: sans(12), color: dark)
            .draw(with: CGRect(x: pad, y: y, width: 390, height: 40), options: .usesLineFragmentOrigin, context: nil)
        y += 46

        if options.sunTimes, let where_ = scenes.lazy.compactMap(place).first {
            let t = sunTimes(at: where_, on: date)
            y = grid([("Sunrise", t.rise, false), ("Golden hour", t.golden, true), ("Sunset", t.set, false), ("Blue hour", t.blue, false)], y: y) + 16
        }

        // Detailed, round 4: the shoot day's weather and the plan in the order the light
        // comes round, instead of the scene table (each scene's map is on its own page).
        if options.tier == .detailed {
            let stops = dayPlan(scenes, on: date)
            if !stops.isEmpty {
                y = shootDayWeather(scenes, on: date, y: y)
                y = drawPlan(stops, firstPage: firstPage, kit: options.kit, y: y + 18)
                let stamp = DateFormatter()
                stamp.locale = Locale(identifier: "en_GB")
                stamp.dateFormat = "d MMM yyyy, HH:mm"
                footer(left: "Exported from Out & Scout · \(stamp.string(from: Date()))", page: 1, of: total)
                return
            }
        }

        // Scene table: #, scene, location, light, shots.
        let cols: [CGFloat] = [pad, pad + 42, page.width - pad - 38 - 12 - 52 - 12 - 158, page.width - pad - 38 - 12 - 52, page.width - pad - 38]
        for (i, h) in ["#", "Scene", "Location", "Light", "Shots"].enumerated() {
            text(h, font: mono(8.5), color: graphite).draw(at: CGPoint(x: cols[i], y: y))
        }
        y += 15
        line(at: y)
        for (i, scene) in scenes.enumerated() {
            if y > page.height - pad - footerH - 50 { break }
            let top = y + 10
            text(String(format: "%02d", i + 1), font: mono(10)).draw(at: CGPoint(x: cols[0], y: top + 2))
            text(scene.name, font: sans(13, medium: true))
                .draw(with: CGRect(x: cols[1], y: top, width: cols[2] - cols[1] - 12, height: 18), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            let pageNote = scene.shots.isEmpty ? "No shots yet" : "Page \(firstPage[scene.id] ?? 2)"
            text([scene.note, pageNote].filter { !$0.isEmpty }.joined(separator: " · "), font: mono(8.5), color: graphite)
                .draw(at: CGPoint(x: cols[1], y: top + 17))
            if let loc = place(of: scene) {
                text(loc.label ?? "", font: mono(8.5)).draw(at: CGPoint(x: cols[2], y: top + 2))
                text(coords(loc), font: mono(8.5), color: graphite).draw(at: CGPoint(x: cols[2], y: top + 14))
            }
            let golden = scene.shots.contains(where: \.isGolden)
            if let light = scene.shots.first.map(lightWord) {
                let word = golden ? "Golden" : light
                if golden { dot(at: CGPoint(x: cols[3], y: top + 5), golden: true) }
                text(word, font: mono(8.5), color: golden ? ink : graphite).draw(at: CGPoint(x: cols[3] + (golden ? 9 : 0), y: top + 2))
            }
            text("\(scene.shots.count)", font: mono(10)).draw(at: CGPoint(x: cols[4], y: top + 2))
            y = top + 34
            line(at: y)
        }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_GB")
        stamp.dateFormat = "d MMM yyyy, HH:mm"
        footer(left: "Exported from Out & Scout · \(stamp.string(from: Date()))", page: 1, of: total)
    }

    // MARK: Summary, 1.1 Paper (the early-October layout, tighter, with the design kit)

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    /// The light chip: B / ¾B / S / ¾F / F, solid for backlit down to an outline for front lit.
    @discardableResult
    static func lightChip(_ k: LightClass?, at p: CGPoint) -> CGFloat {
        let label = k?.letter ?? "–"
        let t = text(label, font: mono(7.5), color: ink)
        let w = max(18, t.size().width + 6), h: CGFloat = 12
        let r = CGRect(x: p.x, y: p.y, width: w, height: h)
        let fill: UIColor? = switch k {
        case .backlit: ink
        case .threeQuarterBack: UIColor(hex: 0x6E6B64)
        case .side: UIColor(hex: 0xB9B5AB)
        case .threeQuarterFront: UIColor(hex: 0xDAD6CD)
        case .front, .none: nil
        }
        if let fill { fill.setFill(); UIRectFill(r) }
        ink.setStroke()
        let b = UIBezierPath(rect: r.insetBy(dx: 0.35, dy: 0.35)); b.lineWidth = 0.7; b.stroke()
        let dark = k == .backlit || k == .threeQuarterBack
        text(label, font: mono(7.5), color: dark ? UIColor(hex: 0xF1EEE7) : ink)
            .draw(at: CGPoint(x: r.midX - t.size().width / 2, y: r.minY + 1.5))
        return w
    }

    /// `◎ place`, `↗ 247° SW` (arrow turned to the heading) or `Maps ↗`: a small outlined tag.
    @discardableResult
    static func tag(_ s: String, at p: CGPoint, heading: Double? = nil, link: URL? = nil,
                    ctx: UIGraphicsPDFRendererContext? = nil, maxWidth: CGFloat = 200) -> CGFloat {
        let t = text(s, font: mono(7), color: ink)
        let arrow: CGFloat = heading == nil ? 0 : 9
        let w = min(maxWidth, t.size().width + 8 + arrow), h: CGFloat = 12
        let r = CGRect(x: p.x, y: p.y, width: w, height: h)
        rule.setStroke()
        let b = UIBezierPath(rect: r.insetBy(dx: 0.3, dy: 0.3)); b.lineWidth = 0.6; b.stroke()
        if let heading, let cg = UIGraphicsGetCurrentContext() {
            cg.saveGState()
            cg.translateBy(x: r.minX + 7.5, y: r.midY)
            cg.rotate(by: heading * .pi / 180)
            let a = UIBezierPath()
            a.move(to: CGPoint(x: 0, y: -4)); a.addLine(to: CGPoint(x: 3, y: 4))
            a.addLine(to: CGPoint(x: 0, y: 2.4)); a.addLine(to: CGPoint(x: -3, y: 4)); a.close()
            ink.setFill(); a.fill()
            cg.restoreGState()
        }
        t.draw(with: CGRect(x: r.minX + 4 + arrow, y: r.minY + 2, width: w - 8 - arrow, height: 10),
               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        if let link, let ctx { ctx.setURL(link, for: r) }
        return w
    }

    /// The day for one heading, sunrise to sunset: grey by how the light falls, golden hour in
    /// orange, a tick at the shot's time.
    static func dayStrip(day: SunDay, heading: Double, mark: Date, in r: CGRect) {
        guard let rise = day.sunrise, let set = day.sunset, set > rise else { return }
        let span = set.timeIntervalSince(rise)
        let x = { (t: Date) in r.minX + CGFloat(min(max(t.timeIntervalSince(rise) / span, 0), 1)) * r.width }
        for w in LightRead.windows(day: day, heading: heading) {
            let shade: UIColor = switch w.light {
            case .backlit: ink
            case .threeQuarterBack: UIColor(hex: 0x6E6B64)
            case .side: UIColor(hex: 0x9C988F)
            case .threeQuarterFront: UIColor(hex: 0xB9B5AB)
            case .front: UIColor(hex: 0xDAD6CD)
            }
            shade.setFill()
            UIRectFill(CGRect(x: x(w.start), y: r.minY, width: max(0.5, x(w.end) - x(w.start)), height: r.height))
        }
        for g in day.goldenWindows {
            sun.setFill()
            UIRectFill(CGRect(x: x(g.lowerBound), y: r.minY, width: max(0.5, x(g.upperBound) - x(g.lowerBound)), height: r.height))
        }
        ink.setFill()
        UIRectFill(CGRect(x: x(mark) - 0.6, y: r.minY - 2, width: 1.2, height: r.height + 4))
    }

    /// Summary cover: the big shot count, the project on an orange rule, the kit, the sun grid,
    /// and the scene table (# · scene + page · place + coordinates · light · shots).
    static func summaryCover(_ ctx: UIGraphicsPDFRendererContext, project: Project, scenes: [ScoutScene],
                             firstPage: [UUID: Int], total: Int, options: Options) {
        let date = recceDate(scenes)
        let w = page.width - pad * 2
        var y = pad + 30
        let shotCount = scenes.reduce(0) { $0 + $1.shots.count }
        let num = text("\(shotCount)", font: big(88), color: sun, kern: -4)
        num.draw(at: CGPoint(x: pad - 4, y: y))
        let nh = num.size().height
        let r1 = text("SHOTS", font: mono(8.5), color: graphite, kern: 0.8)
        r1.draw(at: CGPoint(x: page.width - pad - r1.size().width, y: y + nh - 34))
        let r2 = text("\(scenes.count) SCENE\(scenes.count == 1 ? "" : "S")", font: mono(8.5), color: ink, kern: 0.8)
        r2.draw(at: CGPoint(x: page.width - pad - r2.size().width, y: y + nh - 20))
        y += nh + 2
        line(at: y, color: sun, weight: 1.2)
        y += 6
        text(project.name, font: mono(11), color: ink)
            .draw(with: CGRect(x: pad, y: y, width: w - 140, height: 14), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        let when = text("Recce \(Format.shortDate(date)) \(Calendar.current.component(.year, from: date))", font: mono(9), color: graphite)
        when.draw(at: CGPoint(x: page.width - pad - when.size().width, y: y + 1))
        y += 18
        var kit = [project.kind].filter { !$0.isEmpty }
        if let first = scenes.flatMap(\.shots).first {
            kit += [first.cameraName, first.lensSeries].filter { !$0.isEmpty }
        }
        if !kit.isEmpty {
            text(kit.joined(separator: " · "), font: mono(8.5), color: graphite).draw(at: CGPoint(x: pad, y: y))
            y += 18
        }
        if options.sunTimes, let where_ = scenes.lazy.compactMap(place).first {
            let t = sunTimes(at: where_, on: date)
            y = grid([("Sunrise", t.rise, false), ("Golden", t.golden, true), ("Sunset", t.set, false), ("Blue", t.blue, false)], y: y + 4) + 16
        }

        let cols: [CGFloat] = [pad, pad + 30, pad + 196, page.width - pad - 30 - 64, page.width - pad - 22]
        for (i, h) in ["#", "Scene", "Location", "Light", "Shots"].enumerated() {
            text(h.uppercased(), font: mono(7.5), color: graphite, kern: 0.6).draw(at: CGPoint(x: cols[i], y: y))
        }
        y += 13
        line(at: y, color: ink)
        for (i, scene) in scenes.enumerated() {
            if y > page.height - pad - footerH - 40 { break }
            let top = y + 8
            text(String(format: "%02d", i + 1), font: big(13), color: sun).draw(at: CGPoint(x: cols[0], y: top - 1))
            text(scene.name, font: mono(10.5))
                .draw(with: CGRect(x: cols[1], y: top, width: cols[2] - cols[1] - 10, height: 14), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            text(scene.shots.isEmpty ? "No shots yet" : "Page \(firstPage[scene.id] ?? 2)", font: mono(7.5), color: graphite)
                .draw(at: CGPoint(x: cols[1], y: top + 15))
            if let loc = place(of: scene) {
                tag("◎ \(loc.label ?? "Pinned spot")", at: CGPoint(x: cols[2], y: top - 1), link: loc.mapURL, ctx: ctx, maxWidth: cols[3] - cols[2] - 10)
                text(coords(loc), font: mono(7.5), color: graphite).draw(at: CGPoint(x: cols[2], y: top + 15))
            }
            var lx = cols[3]
            if scene.shots.contains(where: \.isGolden) {
                dot(at: CGPoint(x: lx, y: top + 3.5), golden: true)
                lx += 9
            }
            if let first = scene.shots.first { lightChip(first.lightClass, at: CGPoint(x: lx, y: top)) }
            text("\(scene.shots.count)", font: mono(10)).draw(at: CGPoint(x: cols[4], y: top))
            y = top + 30
            line(at: y)
        }
        footer(left: "Exported from Out & Scout · \(stamp.string(from: Date()))", page: 1, of: total)
    }

    static func drawScene(_ ctx: UIGraphicsPDFRendererContext, project: Project, scene: ScoutScene, index: Int,
                                  startPage pageNo: inout Int, total: Int, options: Options) {
        var y: CGFloat = 0
        // Columns: shot, frame, description, lens, time, light.
        let frameW: CGFloat = options.frames ? 92 : 0
        let cShot = pad
        let cFrame = pad + 30 + 10
        let cDesc = options.frames ? cFrame + frameW + 12 : cFrame
        let cLight = page.width - pad - 70
        let cTime = cLight - 10 - 36
        let cLens = cTime - 10 - 30
        let descW = cLens - 12 - cDesc
        let loc = place(of: scene)
        let date = recceDate([scene])
        let day = loc.map { SunCalculator.day(containing: date, latitude: $0.latitude, longitude: $0.longitude) }

        func header(continued: Bool = false) {
            ctx.beginPage()
            y = pad
            text("\(project.name) · Scene \(String(format: "%02d", index))", font: mono(8), color: graphite).draw(at: CGPoint(x: pad, y: y))
            wordmark(at: CGPoint(x: page.width - pad - wordmarkWidth(size: 10), y: y), size: 10)
            y += 14
            // The scene number big and orange, the name beside it.
            let num = text(String(format: "%02d", index), font: big(continued ? 32 : 52), color: sun, kern: -2)
            num.draw(at: CGPoint(x: pad - 2, y: y))
            let nx = pad + num.size().width + 12
            let nb = y + num.size().height
            text(scene.name + (continued ? " · continued" : ""), font: big(continued ? 14 : 19), kern: -0.5)
                .draw(with: CGRect(x: nx, y: nb - (continued ? 34 : 44), width: page.width - pad - nx, height: 24), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            let when = scene.note.isEmpty ? Format.shortDate(date) : scene.note
            var tx = nx
            let d = text(when, font: mono(8.5), color: graphite)
            d.draw(at: CGPoint(x: tx, y: nb - 18))
            tx += d.size().width + 8
            if let loc {
                tag("◎ \(loc.label ?? coords(loc)) ↗", at: CGPoint(x: tx, y: nb - 19.5), link: loc.mapURL, ctx: ctx, maxWidth: page.width - pad - tx)
            }
            y = nb + 6
            if options.sunTimes, let loc {
                let t = sunTimes(at: loc, on: date)
                line(at: y, color: sun, weight: 1.2)
                y = grid([("Sunrise", t.rise, false), ("Golden", t.golden, true), ("Sunset", t.set, false), ("Location", coords(loc), false)], y: y) + 10
                if !continued {
                    y = sunPathChart(scene: scene, at: loc, on: date, y: y) + 10
                }
            } else {
                line(at: y, color: sun, weight: 1.2)
                y += 10
            }
            for (x, h) in [(cShot, "Shot"), (cFrame, options.frames ? "Frame" : ""), (cDesc, "Description"), (cLens, "Lens"), (cTime, "Time"), (cLight, "Light")] where !h.isEmpty {
                text(h.uppercased(), font: mono(7.5), color: graphite, kern: 0.6).draw(at: CGPoint(x: x, y: y))
            }
            y += 12
            line(at: y, color: ink)
        }

        func finishPage(more: String? = nil) {
            footer(left: more ?? "Exported from Out & Scout", page: pageNo, of: total)
            pageNo += 1
        }

        header()
        if scene.shots.isEmpty {
            text("No shots in this scene yet.", font: mono(10), color: graphite).draw(at: CGPoint(x: pad, y: y + 12))
            finishPage()
            return
        }

        let rowH = rowHeight(options)
        let perPage = rowsPerPage(options)
        for (i, shot) in scene.shots.enumerated() {
            if i > 0, i % perPage == 0 {
                finishPage(more: "\(shot.number) continues on page \(pageNo + 1)")
                header(continued: true)
            }
            let top = y + 8
            text(shot.number, font: big(14), color: ink).draw(at: CGPoint(x: cShot, y: top - 2))
            if shot.isGolden { dot(at: CGPoint(x: cShot + 22, y: top + 3), golden: true) }

            if options.frames {
                // The box takes the shot's frame-line shape (a 9:16 shot stays tall).
                let boxH = rowH - 16
                let aspect = max(shot.aspect.value, 0.3)
                let boxW = min(frameW, boxH * aspect)
                let rect = CGRect(x: cFrame, y: top, width: boxW, height: min(boxH, boxW / aspect))
                if let image = printable(shot, for: rect) {
                    ctx.cgContext.saveGState()
                    UIBezierPath(rect: rect).addClip()
                    // The frame lines crop the still, as on screen.
                    let crop = fitCrop(aspect: shot.aspect.value, in: image.size)
                    image.draw(in: aspectFill(crop: crop, imageSize: image.size, in: rect))
                    ctx.cgContext.restoreGState()
                } else {
                    UIColor(hex: 0xDAD6CD).setFill()
                    UIRectFill(rect)
                }
            }

            // Description: the caption, then the tags (place, heading, Maps), then the day strip.
            var dy = top
            text(shot.caption.isEmpty ? "Untitled" : shot.caption, font: mono(9.5))
                .draw(with: CGRect(x: cDesc, y: dy, width: descW, height: options.frames ? 24 : 12), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            dy += options.frames ? 25 : 13
            if options.frames || shot.location != nil || shot.bearing != nil {
                var tx = cDesc
                if let l = shot.location {
                    tx += tag("◎ \(l.label ?? coords(l))", at: CGPoint(x: tx, y: dy), maxWidth: descW * 0.5) + 4
                }
                if let b = shot.bearing {
                    tx += tag("\(Int(b.rounded()))° \(HeadingTag.short(b))", at: CGPoint(x: tx, y: dy), heading: b) + 4
                }
                if let url = shot.location?.mapURL {
                    tag("Maps ↗", at: CGPoint(x: tx, y: dy), link: url, ctx: ctx)
                }
                dy += 16
            }
            if options.frames, let b = shot.bearing, let l = shot.location {
                let sd = SunCalculator.day(containing: shot.capturedAt, latitude: l.latitude, longitude: l.longitude)
                dayStrip(day: sd, heading: b, mark: shot.plannedTime, in: CGRect(x: cDesc, y: dy + 2, width: min(descW, 150), height: 5))
            } else if options.frames, let b = shot.bearing, let day {
                dayStrip(day: day, heading: b, mark: shot.plannedTime, in: CGRect(x: cDesc, y: dy + 2, width: min(descW, 150), height: 5))
            }

            text(Format.mm(shot.lensMM), font: mono(9)).draw(at: CGPoint(x: cLens, y: top + 1))
            text(Format.time(shot.plannedTime), font: mono(9), color: shot.isGolden ? sun : ink).draw(at: CGPoint(x: cTime, y: top + 1))
            let cw = lightChip(shot.lightClass, at: CGPoint(x: cLight, y: top))
            _ = cw
            // Where the sun sits in the frame, not its degrees (Elliot: degrees belong on the Viewfinder).
            text(shot.sunSide ?? lightWord(shot), font: mono(7.5), color: graphite)
                .draw(with: CGRect(x: cLight, y: top + 15, width: 70, height: 20), options: .usesLineFragmentOrigin, context: nil)

            y += rowH
            line(at: y)
        }
        finishPage()
    }

    /// Shrinks a 12MP still to what the thumbnail needs at print resolution and makes it a
    /// JPEG, which the PDF embeds as is. Drawing the full still made each page tens of MB.
    static func printable(_ shot: Shot, for rect: CGRect) -> UIImage? {
        // Read small from the file and let go of it at once: decoding every full still in
        // one go is what stalled a 66-shot export.
        autoreleasepool { () -> UIImage? in
            let px = min(2400, max(rect.width, rect.height) * 6)
            guard let small = ThumbCache.downsampled(for: shot, maxPixel: px) else { return nil }
            return small.jpegData(compressionQuality: 0.8).flatMap(UIImage.init(data:))
        }
    }

    static func printable(_ image: UIImage, for rect: CGRect) -> UIImage? {
        let fill = aspectFill(image.size, in: rect).size
        let target = CGSize(width: fill.width * 3, height: fill.height * 3)
        let small = image.size.width > target.width ? (image.preparingThumbnail(of: target) ?? image) : image
        return small.jpegData(compressionQuality: 0.8).flatMap(UIImage.init(data:))
    }

    /// Where to draw an image of `imageSize` so that its `crop` region fills `rect`.
    static func aspectFill(crop: CGRect, imageSize: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / crop.width, rect.height / crop.height)
        return CGRect(x: rect.midX - crop.midX * scale, y: rect.midY - crop.midY * scale,
                      width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// The largest centred region of `aspect` inside `size`.
    static func fitCrop(aspect: Double, in size: CGSize) -> CGRect {
        guard aspect > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        var w = size.width
        var h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
