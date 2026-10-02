import UIKit

/// Builds the shot list files. PDF: a cover plus a page per scene. CSV: a row per shot.
enum Exporter {
    enum FileFormat: String, CaseIterable {
        case pdf, csv
    }

    struct Options {
        var frames = true
        var sunTimes = true
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
        let file = name.map { cleanName($0) }.flatMap { $0.isEmpty ? nil : "\($0).\(format.rawValue)" }
            ?? filename(project: project, scene: scene, format: format)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file)
        switch format {
        case .csv:
            // The BOM tells Excel it's UTF-8, so "°" and "·" survive.
            try ("\u{FEFF}" + csv(project: project, scenes: scenes, options: options)).data(using: .utf8)!.write(to: url, options: .atomic)
        case .pdf:
            try pdf(project: project, scenes: scenes, options: options).write(to: url, options: .atomic)
        }
        return url
    }

    // MARK: CSV

    static func csv(project: Project, scenes: [ScoutScene], options: Options) -> String {
        var header = ["project", "scene", "shot", "caption", "lens_mm", "aspect", "camera", "lens_set", "time", "light"]
        if options.sunTimes { header += ["sun_azimuth", "sun_elevation"] }
        header += ["bearing", "location", "postcode", "latitude", "longitude", "map_link", "pinned_at"]

        let iso = ISO8601DateFormatter()
        var lines = [header.joined(separator: ",")]
        for scene in scenes {
            for shot in scene.shots {
                var row: [String] = [
                    project.name, scene.name, shot.number, shot.caption,
                    Format.mm(shot.lensMM), shot.aspect.label, shot.cameraName, shot.lensSeries,
                    Format.time(shot.plannedTime), shot.light.label,
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

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: PDF

    private static let page = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 in points

    private static let ink = UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
    private static let graphite = UIColor(red: 0x66 / 255, green: 0x66 / 255, blue: 0x5F / 255, alpha: 1)
    private static let rule = UIColor(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD3 / 255, alpha: 1)
    private static let sun = UIColor(red: 1, green: 0x5A / 255, blue: 0x1F / 255, alpha: 1)

    private static func sans(_ size: CGFloat, medium: Bool = false) -> UIFont {
        UIFont(name: medium ? "Geist-Medium" : "Geist-Regular", size: size)
            ?? .systemFont(ofSize: size, weight: medium ? .medium : .regular)
    }

    private static func mono(_ size: CGFloat) -> UIFont {
        UIFont(name: "GeistMono-Regular", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // Layout follows the "08 PDF · cover" and "09 PDF · scene page" boards (794px wide),
    // scaled to A4 points (× 0.75).
    private static let pad: CGFloat = 42
    private static let dark = UIColor(red: 0x33 / 255, green: 0x33 / 255, blue: 0x2F / 255, alpha: 1)
    private static let footerH: CGFloat = 20

    /// Shots per scene page, from the row height.
    private static func rowHeight(_ options: Options) -> CGFloat { options.frames ? 84 : 40 }
    private static func rowsPerPage(_ options: Options) -> Int {
        // Room under the scene header and sun grid, above the footer.
        let avail = page.height - pad * 2 - 168 - footerH
        return max(1, Int(avail / rowHeight(options)))
    }
    private static func pages(for scene: ScoutScene, _ options: Options) -> Int {
        max(1, Int(ceil(Double(scene.shots.count) / Double(rowsPerPage(options)))))
    }

    static func pdf(project: Project, scenes: [ScoutScene], options: Options) -> Data {
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

    private static func text(_ s: String, font: UIFont, color: UIColor = ink, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    private static func line(at y: CGFloat, color: UIColor = rule, weight: CGFloat = 0.75) {
        color.setFill()
        UIRectFill(CGRect(x: pad, y: y, width: page.width - pad * 2, height: weight))
    }

    private static func dot(at p: CGPoint, golden: Bool, size: CGFloat = 5) {
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

    private static func footer(left: String, page pageNo: Int, of total: Int) {
        let y = page.height - pad - 9
        text(left, font: mono(8.5), color: graphite).draw(at: CGPoint(x: pad, y: y))
        let right = text("page \(pageNo) of \(total)", font: mono(8.5), color: graphite)
        right.draw(at: CGPoint(x: page.width - pad - right.size().width, y: y))
    }

    /// Four label/value cells between an ink rule and a light rule.
    private static func grid(_ cells: [(label: String, value: String, golden: Bool)], y: CGFloat) -> CGFloat {
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

    /// Sunrise, the evening golden and blue hours, and sunset for a place on the recce day.
    private static func sunTimes(at loc: ShotLocation?, on date: Date) -> (rise: String, golden: String, set: String, blue: String) {
        guard let loc else { return ("–", "–", "–", "–") }
        let day = SunCalculator.day(containing: date, latitude: loc.latitude, longitude: loc.longitude)
        let span = { (r: ClosedRange<Date>?) in r.map { "\(Format.time($0.lowerBound)) – \(Format.time($0.upperBound))" } ?? "–" }
        return (day.sunrise.map { Format.time($0) } ?? "–", span(day.goldenWindows.last),
                day.sunset.map { Format.time($0) } ?? "–", span(day.blueWindows.last))
    }

    private static func place(of scene: ScoutScene) -> ShotLocation? {
        scene.location ?? scene.shots.first(where: { $0.location != nil })?.location
    }

    private static func recceDate(_ scenes: [ScoutScene]) -> Date {
        scenes.flatMap(\.shots).map(\.capturedAt).min() ?? Date()
    }

    private static func coords(_ loc: ShotLocation) -> String {
        String(format: "%.4f°%@ %.4f°%@", abs(loc.latitude), loc.latitude >= 0 ? "N" : "S",
               abs(loc.longitude), loc.longitude >= 0 ? "E" : "W")
    }

    private static func lightWord(_ shot: Shot) -> String {
        shot.light == .goldenHour ? "golden" : shot.light.label
    }

    private static func drawCover(_ ctx: UIGraphicsPDFRendererContext, project: Project, scenes: [ScoutScene],
                                  firstPage: [UUID: Int], total: Int, options: Options) {
        ctx.beginPage()
        let w = page.width - pad * 2
        let date = recceDate(scenes)
        text("out & scout", font: sans(11, medium: true), kern: -0.2).draw(at: CGPoint(x: pad, y: pad))
        let scope = text("shot list · \(scenes.count == 1 ? scenes[0].name : "all scenes")", font: mono(8.5), color: graphite)
        scope.draw(at: CGPoint(x: page.width - pad - scope.size().width, y: pad + 2))

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
            kitLine.append("camera \(first.cameraName.lowercased())")
            kitLine.append("lenses \(first.lensSeries.lowercased())")
        }
        text(kitLine.joined(separator: " · "), font: sans(12), color: dark)
            .draw(with: CGRect(x: pad, y: y, width: 390, height: 40), options: .usesLineFragmentOrigin, context: nil)
        y += 46

        if options.sunTimes {
            let t = sunTimes(at: scenes.lazy.compactMap(place).first, on: date)
            y = grid([("sunrise", t.rise, false), ("golden hour", t.golden, true), ("sunset", t.set, false), ("blue hour", t.blue, false)], y: y) + 16
        }

        // Scene table: #, scene, location, light, shots.
        let cols: [CGFloat] = [pad, pad + 42, page.width - pad - 38 - 12 - 52 - 12 - 158, page.width - pad - 38 - 12 - 52, page.width - pad - 38]
        for (i, h) in ["#", "scene", "location", "light", "shots"].enumerated() {
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
            let pageNote = scene.shots.isEmpty ? "no shots yet" : "page \(firstPage[scene.id] ?? 2)"
            text([scene.note, pageNote].filter { !$0.isEmpty }.joined(separator: " · "), font: mono(8.5), color: graphite)
                .draw(at: CGPoint(x: cols[1], y: top + 17))
            if let loc = place(of: scene) {
                text(loc.label ?? "", font: mono(8.5)).draw(at: CGPoint(x: cols[2], y: top + 2))
                text(coords(loc), font: mono(8.5), color: graphite).draw(at: CGPoint(x: cols[2], y: top + 14))
            }
            let golden = scene.shots.contains(where: \.isGolden)
            if let light = scene.shots.first.map(lightWord) {
                let word = golden ? "golden" : light
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
        footer(left: "exported from out & scout · \(stamp.string(from: Date()).lowercased())", page: 1, of: total)
    }

    private static func drawScene(_ ctx: UIGraphicsPDFRendererContext, project: Project, scene: ScoutScene, index: Int,
                                  startPage pageNo: inout Int, total: Int, options: Options) {
        var y: CGFloat = 0
        // Columns: shot, frame, description, lens, time, light.
        let frameW: CGFloat = options.frames ? 99 : 0
        let cShot = pad
        let cFrame = pad + 36 + 12
        let cDesc = options.frames ? cFrame + frameW + 12 : cFrame
        let cLight = page.width - pad - 82
        let cTime = cLight - 12 - 48
        let cLens = cTime - 12 - 48
        let descW = cLens - 12 - cDesc

        func header() {
            ctx.beginPage()
            y = pad
            text("\(project.name) · scene \(String(format: "%02d", index))", font: mono(8.5), color: graphite).draw(at: CGPoint(x: pad, y: y))
            let brand = text("out & scout", font: sans(11, medium: true), kern: -0.2)
            brand.draw(at: CGPoint(x: page.width - pad - brand.size().width, y: y))
            y += 14
            text(scene.name, font: sans(26, medium: true), kern: -0.8)
                .draw(with: CGRect(x: pad, y: y, width: page.width - pad * 2 - 80, height: 34), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            y += 34
            let loc = place(of: scene)
            let sub = [scene.note, Format.shortDate(recceDate([scene])), loc?.display].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            text(sub, font: mono(9), color: graphite)
                .draw(with: CGRect(x: pad, y: y, width: page.width - pad * 2, height: 12), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            y += 22
            if options.sunTimes {
                let t = sunTimes(at: loc, on: recceDate([scene]))
                let coordsText = loc.map { String(format: "%.2f°%@ %.2f°%@", abs($0.latitude), $0.latitude >= 0 ? "N" : "S", abs($0.longitude), $0.longitude >= 0 ? "E" : "W") } ?? "–"
                y = grid([("sunrise", t.rise, false), ("golden hour", t.golden, false), ("sunset", t.set, false), ("location", coordsText, false)], y: y) + 14
            }
            for (x, h) in [(cShot, "shot"), (cFrame, options.frames ? "frame" : ""), (cDesc, "description"), (cLens, "lens"), (cTime, "time"), (cLight, "light")] where !h.isEmpty {
                text(h, font: mono(8.5), color: graphite).draw(at: CGPoint(x: x, y: y))
            }
            y += 14
            line(at: y)
        }

        func finishPage() {
            footer(left: "exported from out & scout", page: pageNo, of: total)
            pageNo += 1
        }

        header()
        if scene.shots.isEmpty {
            text("No shots in this scene yet.", font: sans(11), color: graphite).draw(at: CGPoint(x: pad, y: y + 12))
            finishPage()
            return
        }

        let rowH = rowHeight(options)
        let perPage = rowsPerPage(options)
        for (i, shot) in scene.shots.enumerated() {
            if i > 0, i % perPage == 0 {
                finishPage()
                header()
            }
            let top = y + 9
            let midY = top + (rowH - 18) / 2
            text(shot.number, font: sans(13.5, medium: true)).draw(at: CGPoint(x: cShot, y: midY - 8))

            if options.frames {
                let rect = CGRect(x: cFrame, y: top, width: frameW, height: rowH - 18)
                if let image = ThumbCache.full(for: shot).flatMap({ printable($0, for: rect) }) {
                    ctx.cgContext.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: 3).addClip()
                    // The frame lines crop the still, as on screen.
                    let crop = fitCrop(aspect: shot.aspect.value, in: image.size)
                    image.draw(in: aspectFill(crop: crop, imageSize: image.size, in: rect))
                    ctx.cgContext.restoreGState()
                } else {
                    UIColor(red: 0x2B / 255, green: 0x2B / 255, blue: 0x28 / 255, alpha: 1).setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()
                }
            }

            // Description: the caption, then where it was shot with a map link.
            var dy = options.frames ? top + 6 : top
            text(shot.caption.isEmpty ? "untitled" : shot.caption, font: sans(10.5))
                .draw(with: CGRect(x: cDesc, y: dy, width: descW, height: 28), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            dy += options.frames ? 30 : 14
            if let loc = shot.location {
                var whereText = loc.label ?? coords(loc)
                if let bearing = shot.bearing { whereText += " · facing \(Format.bearing(bearing))" }
                text(whereText, font: mono(8), color: graphite)
                    .draw(with: CGRect(x: cDesc, y: dy, width: descW, height: 11), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                if let url = loc.mapURL, options.frames {
                    let link = text("open in maps ↗", font: mono(8))
                    let linkRect = CGRect(origin: CGPoint(x: cDesc, y: dy + 13), size: link.size())
                    link.draw(at: linkRect.origin)
                    ctx.setURL(url, for: linkRect)
                }
            }

            text("\(Format.mm(shot.lensMM))mm", font: mono(9)).draw(at: CGPoint(x: cLens, y: midY - 5))
            text(Format.time(shot.plannedTime), font: mono(9)).draw(at: CGPoint(x: cTime, y: midY - 5))
            if shot.isGolden { dot(at: CGPoint(x: cLight, y: midY - 1), golden: true) }
            var lightText = lightWord(shot)
            if options.sunTimes { lightText += "\nsun \(Int(shot.sunAzimuth.rounded()))° / \(Int(shot.sunElevation.rounded()))°" }
            text(lightText, font: mono(9), color: shot.isGolden ? ink : graphite)
                .draw(with: CGRect(x: cLight + (shot.isGolden ? 9 : 0), y: midY - 5, width: 82, height: 26), options: .usesLineFragmentOrigin, context: nil)

            y += rowH
            line(at: y)
        }
        finishPage()
    }

    /// Shrinks a 12MP still to what the thumbnail needs at print resolution and makes it a
    /// JPEG, which the PDF embeds as is. Drawing the full still made each page tens of MB.
    private static func printable(_ image: UIImage, for rect: CGRect) -> UIImage? {
        let fill = aspectFill(image.size, in: rect).size
        let target = CGSize(width: fill.width * 3, height: fill.height * 3)
        let small = image.size.width > target.width ? (image.preparingThumbnail(of: target) ?? image) : image
        return small.jpegData(compressionQuality: 0.8).flatMap(UIImage.init(data:))
    }

    /// Where to draw an image of `imageSize` so that its `crop` region fills `rect`.
    private static func aspectFill(crop: CGRect, imageSize: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / crop.width, rect.height / crop.height)
        return CGRect(x: rect.midX - crop.midX * scale, y: rect.midY - crop.midY * scale,
                      width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// The largest centred region of `aspect` inside `size`.
    private static func fitCrop(aspect: Double, in size: CGSize) -> CGRect {
        guard aspect > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        var w = size.width
        var h = w / aspect
        if h > size.height { h = size.height; w = h * aspect }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
