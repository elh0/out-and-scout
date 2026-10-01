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
    private static let margin: CGFloat = 48

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

    static func pdf(project: Project, scenes: [ScoutScene], options: Options) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            drawCover(ctx, project: project, scenes: scenes)
            for scene in scenes {
                drawScene(ctx, project: project, scene: scene, options: options)
            }
        }
    }

    private static func text(_ s: String, font: UIFont, color: UIColor = ink) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    }

    private static func line(at y: CGFloat) {
        rule.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: page.width - margin * 2, height: 0.5))
    }

    private static func drawCover(_ ctx: UIGraphicsPDFRendererContext, project: Project, scenes: [ScoutScene]) {
        ctx.beginPage()
        let w = page.width - margin * 2
        text("out & scout", font: sans(14, medium: true)).draw(at: CGPoint(x: margin, y: margin))

        // The sun mark: a dot on a thin horizon.
        rule.setFill()
        UIRectFill(CGRect(x: page.width - margin - 40, y: margin + 14, width: 40, height: 1))
        sun.setFill()
        UIBezierPath(ovalIn: CGRect(x: page.width - margin - 26, y: margin + 3, width: 12, height: 12)).fill()

        var y: CGFloat = 300
        text("shot list", font: mono(11), color: graphite).draw(at: CGPoint(x: margin, y: y))
        y += 20
        let title = text(project.name, font: sans(44, medium: true))
        title.draw(with: CGRect(x: margin, y: y, width: w, height: 120), options: .usesLineFragmentOrigin, context: nil)
        y += 64
        let shotCount = scenes.reduce(0) { $0 + $1.shots.count }
        let sub = [project.kind, "\(scenes.count) scene\(scenes.count == 1 ? "" : "s")", "\(shotCount) shots", Format.shortDate(Date())]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        text(sub, font: sans(14), color: graphite).draw(at: CGPoint(x: margin, y: y))

        y = 520
        line(at: y)
        y += 12
        for scene in scenes {
            text(scene.name, font: sans(14, medium: true)).draw(at: CGPoint(x: margin, y: y))
            let right = text(ShotListView.shots(scene.shots.count), font: mono(10), color: graphite)
            right.draw(at: CGPoint(x: page.width - margin - right.size().width, y: y + 3))
            if let loc = scene.location?.label {
                text(loc, font: mono(10), color: graphite).draw(at: CGPoint(x: margin + 200, y: y + 3))
            }
            y += 28
            line(at: y - 8)
            if y > page.height - margin - 40 { break }
        }

        text("filled dot: golden hour · ring: other light", font: mono(9), color: graphite)
            .draw(at: CGPoint(x: margin, y: page.height - margin))
    }

    private static func drawScene(_ ctx: UIGraphicsPDFRendererContext, project: Project, scene: ScoutScene, options: Options) {
        let w = page.width - margin * 2
        var y: CGFloat = 0

        func header() {
            ctx.beginPage()
            y = margin
            text("\(project.name) / ", font: sans(12), color: graphite).draw(at: CGPoint(x: margin, y: y))
            y += 18
            text(scene.name, font: sans(28, medium: true)).draw(at: CGPoint(x: margin, y: y))
            y += 38
            let sub = [scene.note, scene.location?.display].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !sub.isEmpty {
                text(sub, font: mono(9), color: graphite).draw(at: CGPoint(x: margin, y: y))
                y += 18
            }
            line(at: y)
            y += 12
        }

        header()
        if scene.shots.isEmpty {
            text("No shots in this scene yet.", font: sans(12), color: graphite).draw(at: CGPoint(x: margin, y: y))
            return
        }

        let thumbW: CGFloat = options.frames ? 168 : 0
        for shot in scene.shots {
            let thumbH = options.frames ? thumbW / max(shot.aspect.value, 0.5) : 0
            let rowH = max(thumbH, 78) + 16
            if y + rowH > page.height - margin { header() }

            var x = margin
            if options.frames {
                let rect = CGRect(x: x, y: y, width: thumbW, height: thumbH)
                if let image = ThumbCache.full(for: shot).flatMap({ printable($0, for: rect) }) {
                    ctx.cgContext.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: 3).addClip()
                    image.draw(in: aspectFill(image.size, in: rect))
                    ctx.cgContext.restoreGState()
                } else {
                    UIColor(white: 0.17, alpha: 1).setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()
                }
                x += thumbW + 16
            }

            let textW = w - (x - margin) - 20
            text(shot.number, font: mono(10), color: graphite).draw(at: CGPoint(x: x, y: y))
            text(shot.caption, font: sans(14, medium: true))
                .draw(with: CGRect(x: x, y: y + 14, width: textW, height: 20), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            var meta = "\(shot.aspect.label) · \(Format.mm(shot.lensMM))mm · \(Format.time(shot.plannedTime)) · \(shot.light.label)"
            if options.sunTimes { meta += " · sun \(Int(shot.sunAzimuth.rounded()))° / \(Int(shot.sunElevation.rounded()))°" }
            text(meta, font: mono(9), color: graphite)
                .draw(with: CGRect(x: x, y: y + 36, width: textW, height: 24), options: .usesLineFragmentOrigin, context: nil)
            // Where it was shot: place, coordinates and which way the camera faced, plus a
            // tappable map link.
            if let loc = shot.location {
                var whereText = loc.display
                if let bearing = shot.bearing { whereText += " · facing \(Format.bearing(bearing))" }
                let place = text(whereText, font: mono(9), color: graphite)
                let placeRect = CGRect(x: x, y: y + 50, width: textW, height: 12)
                place.draw(with: placeRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                if let url = loc.mapURL {
                    let link = text("open in maps ↗", font: mono(9), color: ink)
                    let linkRect = CGRect(origin: CGPoint(x: x, y: y + 63), size: link.size())
                    link.draw(at: linkRect.origin)
                    ctx.setURL(url, for: linkRect)
                }
            } else if let bearing = shot.bearing {
                text("facing \(Format.bearing(bearing))", font: mono(9), color: graphite).draw(at: CGPoint(x: x, y: y + 50))
            }

            // Light dot
            let dot = CGRect(x: page.width - margin - 8, y: y + 2, width: 8, height: 8)
            if shot.isGolden {
                sun.setFill()
                UIBezierPath(ovalIn: dot).fill()
            } else {
                graphite.setStroke()
                let p = UIBezierPath(ovalIn: dot.insetBy(dx: 0.75, dy: 0.75))
                p.lineWidth = 1.5
                p.stroke()
            }

            y += rowH
            line(at: y - 8)
        }
    }

    /// Shrinks a 12MP still to what the thumbnail needs at print resolution and makes it a
    /// JPEG, which the PDF embeds as is. Drawing the full still made each page tens of MB.
    private static func printable(_ image: UIImage, for rect: CGRect) -> UIImage? {
        let fill = aspectFill(image.size, in: rect).size
        let target = CGSize(width: fill.width * 3, height: fill.height * 3)
        let small = image.size.width > target.width ? (image.preparingThumbnail(of: target) ?? image) : image
        return small.jpegData(compressionQuality: 0.8).flatMap(UIImage.init(data:))
    }

    private static func aspectFill(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = max(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
