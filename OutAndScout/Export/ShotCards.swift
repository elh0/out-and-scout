import CoreImage
import MapKit
import SwiftUI
import UIKit

// The Detailed and Photos only PDFs, from the approved export prototype (prototype/export.html,
// spec in prototype/export-spec.md, Elliot 6 Oct 2026). Sizes are the prototype's 794px page
// scaled to A4 points (× 0.75). All Geist Mono; orange only for the sun, golden hour and the
// shot time.
extension Exporter {
    // MARK: Wordmark

    /// The locked "Out & Sc●out", drawn from the same outlines as the app. `at` is its top left.
    static func wordmark(at origin: CGPoint, size: CGFloat, color: UIColor = ink) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let top: CGFloat = 0.8
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y)
        cg.scaleBy(x: size, y: size)
        cg.translateBy(x: 0, y: top)
        cg.addPath(WordmarkGlyphs.left.cgPath)
        cg.setFillColor(color.cgColor)
        cg.fillPath()
        let sunX = WordmarkGlyphs.leftWidth + 0.45
        cg.setFillColor(sun.cgColor)
        cg.fillEllipse(in: CGRect(x: sunX, y: -0.55 - 0.22, width: 0.22, height: 0.22))
        cg.translateBy(x: sunX + 0.22 + 0.5, y: 0)
        cg.addPath(WordmarkGlyphs.right.cgPath)
        cg.setFillColor(color.cgColor)
        cg.fillPath()
        cg.restoreGState()
    }

    static func wordmarkWidth(size: CGFloat) -> CGFloat {
        (WordmarkGlyphs.leftWidth + 0.45 + 0.22 + 0.5 + WordmarkGlyphs.rightWidth) * size
    }

    /// Small spaced capitals, the prototype's `.k` label.
    static func caps(_ s: String, size: CGFloat = 6.75, color: UIColor = grey) -> NSAttributedString {
        text(s.uppercased(), font: mono(size), color: color, kern: size * 0.12)
    }

    static let grey = UIColor(red: 0x8C / 255, green: 0x8A / 255, blue: 0x83 / 255, alpha: 1)
    static let hair = UIColor(red: 0xD6 / 255, green: 0xD5 / 255, blue: 0xCF / 255, alpha: 1)

    // MARK: Detailed: cover, then two shot cards a page

    static func detailedPDF(project: Project, scenes: [ScoutScene], options: Options) -> Data {
        // Each scene opens with its day (sun times, the sun path with every shot on it, the
        // shots in order), then its cards two a page.
        let filled = scenes.enumerated().filter { !$0.element.shots.isEmpty }
        var firstPage: [UUID: Int] = [:]
        var next = 2
        for (_, sc) in filled {
            firstPage[sc.id] = next
            next += 1 + Int(ceil(Double(sc.shots.count) / 2))
        }
        let total = max(2, next - 1)
        let cardPad: CGFloat = 36
        let cardH = (page.height - cardPad * 2 - 24 - 24) / 2
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        func pageFooter(_ n: Int, legend: Bool) {
            let fy = page.height - cardPad - 8
            if legend {
                text("B backlit · ¾B · S side · ¾F · F front lit · orange: golden hour and shot time · black: best time",
                     font: mono(6.75), color: grey).draw(at: CGPoint(x: cardPad, y: fy))
            }
            let t = text("\(n) / \(total)", font: mono(6.75), color: grey)
            t.draw(at: CGPoint(x: page.width - cardPad - t.size().width, y: fy))
        }

        return renderer.pdfData { ctx in
            drawCover(ctx, project: project, scenes: scenes, firstPage: firstPage, total: total, options: options)
            if filled.isEmpty {
                ctx.beginPage()
                wordmark(at: CGPoint(x: cardPad, y: cardPad), size: 10)
                text("No shots yet.", font: mono(9), color: grey).draw(at: CGPoint(x: cardPad, y: cardPad + 40))
                pageFooter(2, legend: false)
                return
            }
            var pageNo = 2
            for (i, scene) in filled {
                ctx.beginPage()
                sceneDay(scene, index: i + 1, project: project, kit: options.kit, start: pageNo, ctx: ctx)
                pageFooter(pageNo, legend: false)
                pageNo += 1
                let pages = Int(ceil(Double(scene.shots.count) / 2))
                for p in 0..<pages {
                    ctx.beginPage()
                    wordmark(at: CGPoint(x: cardPad, y: cardPad), size: 10)
                    let k = caps("\(project.name) · \(scene.name)")
                    k.draw(at: CGPoint(x: page.width - cardPad - k.size().width, y: cardPad + 1))
                    for (j, shot) in scene.shots.dropFirst(p * 2).prefix(2).enumerated() {
                        card(shot, scene: scene, sceneIndex: i + 1, kit: options.kit,
                             in: CGRect(x: cardPad, y: cardPad + 24 + CGFloat(j) * cardH, width: page.width - cardPad * 2, height: cardH), ctx: ctx)
                    }
                    pageFooter(pageNo, legend: true)
                    pageNo += 1
                }
            }
        }
    }

    /// A scene's opening page: name and place, the sun times, the sun path with each shot's
    /// sun and heading on it, then the shots in order with their time and light read.
    private static func sceneDay(_ scene: ScoutScene, index: Int, project: Project, kit: Kit, start: Int, ctx: UIGraphicsPDFRendererContext) {
        wordmark(at: CGPoint(x: pad, y: pad), size: 10)
        let k = caps("\(project.name) · scene \(String(format: "%02d", index))")
        k.draw(at: CGPoint(x: page.width - pad - k.size().width, y: pad + 1))
        var y = pad + 40
        text(scene.name, font: mono(21), kern: -0.4)
            .draw(with: CGRect(x: pad, y: y, width: page.width - pad * 2, height: 28), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        y += 30
        let loc = place(of: scene)
        let date = recceDate([scene])
        let sub = [scene.note.isEmpty ? Format.shortDate(date) : scene.note, loc?.display, ShotListView.shots(scene.shots.count)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        text(sub, font: mono(8.25), color: grey)
            .draw(with: CGRect(x: pad, y: y, width: page.width - pad * 2, height: 12), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        y += 14
        if let url = loc?.mapURL {
            let link = text("Open in Maps ↗", font: mono(8.25))
            let rect = CGRect(origin: CGPoint(x: pad, y: y), size: link.size())
            link.draw(at: rect.origin)
            ink.setFill()
            UIRectFill(CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: 0.5))
            ctx.setURL(url, for: rect.insetBy(dx: -4, dy: -6))
        }
        y += 22

        guard let loc else {
            text("No location saved, so no sun path for this scene.", font: mono(8.25), color: grey).draw(at: CGPoint(x: pad, y: y))
            return
        }
        let t = sunTimes(at: loc, on: date)
        y = grid([("Sunrise", t.rise, false), ("Golden hour", t.golden, true), ("Sunset", t.set, false), ("Blue hour", t.blue, false)], y: y) + 14
        // The week's weather, when forecasts are on and it was fetched for this export.
        if Forecast.allowed, let days = Forecast.cached(latitude: loc.latitude, longitude: loc.longitude), !days.isEmpty {
            y = weatherStrip(Array(days.prefix(7)), y: y) + 14
        }
        // The map, when it can be fetched: every shot where it was taken, facing its way.
        let mapRect = CGRect(x: pad, y: y, width: page.width - pad * 2, height: 176)
        if shotMap(scene, around: loc, kit: kit, in: mapRect, ctx: ctx) { y = mapRect.maxY + 16 }
        y = dayChart(scene, at: loc, on: date, y: y) + 22

        // The shots in order, the light said in plain words.
        let cols: [CGFloat] = [pad, pad + 34, pad + 76, page.width - pad - 236, page.width - pad - 26]
        for (i, h) in ["Shot", "Time", "Caption", "The light", "Page"].enumerated() {
            caps(h).draw(at: CGPoint(x: cols[i], y: y))
        }
        y += 12
        let bottom = page.height - 36 - 24
        for (n, shot) in scene.shots.enumerated() {
            if y + 18 > bottom {
                text("+ \(scene.shots.count - n) more on the cards", font: mono(7.5), color: grey).draw(at: CGPoint(x: pad, y: y + 4))
                break
            }
            hair.setFill()
            UIRectFill(CGRect(x: pad, y: y, width: page.width - pad * 2, height: 0.5))
            let ty = y + 4
            let one: NSStringDrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
            text(shot.number, font: mono(8.25)).draw(at: CGPoint(x: cols[0], y: ty))
            text(Format.time(shot.plannedTime), font: mono(8.25), color: shot.isGolden ? sun : ink).draw(at: CGPoint(x: cols[1], y: ty))
            text(shot.caption.isEmpty ? "Untitled" : shot.caption, font: mono(8.25))
                .draw(with: CGRect(x: cols[2], y: ty, width: cols[3] - cols[2] - 10, height: 11), options: one, context: nil)
            text(plainLight(shot), font: mono(8.25), color: shot.lightClass == nil ? grey : ink)
                .draw(with: CGRect(x: cols[3], y: ty, width: cols[4] - cols[3] - 10, height: 11), options: one, context: nil)
            text("\(start + 1 + n / 2)", font: mono(8.25), color: grey).draw(at: CGPoint(x: cols[4], y: ty))
            y += 18
        }
    }

    /// The light for someone who isn't a DP: "low sun, behind the camera", "golden hour, sun on the left".
    static func plainLight(_ shot: Shot) -> String {
        guard shot.sunElevation > -1 else {
            let m = MoonCalculator.info(at: shot.plannedTime, latitude: shot.location?.latitude ?? 0, longitude: shot.location?.longitude ?? 0)
            return "after sunset · \(m.phaseName.lowercased()), \(Int((m.illumination * 100).rounded()))% lit"
        }
        guard let k = shot.lightClass, let b = shot.bearing else { return "no compass heading saved" }
        let side = LightRead.rel(sunAzimuth: shot.sunAzimuth, heading: b) > 0 ? "right" : "left"
        let where_: String
        switch k {
        case .backlit: where_ = "sun facing the camera"
        case .threeQuarterBack: where_ = "sun ahead, to the \(side)"
        case .side: where_ = "sun on the \(side)"
        case .threeQuarterFront: where_ = "sun behind, to the \(side)"
        case .front: where_ = "sun behind the camera"
        }
        let height = shot.isGolden ? "golden hour" : shot.sunElevation < 15 ? "low sun" : shot.sunElevation > 45 ? "high sun" : nil
        return [height, where_].compactMap { $0 }.joined(separator: ", ")
    }

    private static func card(_ shot: Shot, scene: ScoutScene, sceneIndex: Int, kit: Kit, in r: CGRect, ctx: UIGraphicsPDFRendererContext) {
        ink.setFill()
        UIRectFill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 0.75))
        var y = r.minY + 9

        // 6A  caption ................ 02 · Scene 6
        let id = text(shot.number, font: mono(18), kern: -0.36)
        id.draw(at: CGPoint(x: r.minX, y: y))
        let where_ = text("\(String(format: "%02d", sceneIndex)) · \(scene.name)", font: mono(8.25), color: grey)
        var right = r.maxX
        // A tappable link to the spot, as on the Summary.
        if let url = (shot.location ?? place(of: scene))?.mapURL {
            let link = text("Open in Maps ↗", font: mono(8.25))
            let lw = link.size().width
            let rect = CGRect(x: right - lw, y: y + 7, width: lw, height: link.size().height)
            link.draw(at: rect.origin)
            ink.setFill()
            UIRectFill(CGRect(x: rect.minX, y: rect.maxY, width: lw, height: 0.5))
            ctx.setURL(url, for: rect.insetBy(dx: -4, dy: -6))
            right -= lw + 14
        }
        where_.draw(at: CGPoint(x: right - where_.size().width, y: y + 7))
        right -= where_.size().width
        let capX = r.minX + id.size().width + 10
        text(shot.caption.isEmpty ? "Untitled" : shot.caption, font: mono(9))
            .draw(with: CGRect(x: capX, y: y + 6, width: right - 12 - capX, height: 12),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        y += 30

        // The frame, cropped to its lines.
        let imgRect = CGRect(x: r.minX, y: y, width: 315, height: 177)
        if let image = ThumbCache.full(for: shot).flatMap({ printable($0, for: imgRect) }) {
            ctx.cgContext.saveGState()
            UIRectClip(imgRect)
            let crop = fitCrop(aspect: shot.aspect.value, in: image.size)
            image.draw(in: aspectFill(crop: crop, imageSize: image.size, in: imgRect))
            ctx.cgContext.restoreGState()
        } else {
            UIColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1).setFill()
            UIRectFill(imgRect)
        }

        // Right column: light now with the plan, then when to be there.
        let cx = imgRect.maxX + 15
        let cw = r.maxX - cx
        let loc = shot.location ?? place(of: scene)
        let day = loc.map { SunCalculator.day(containing: shot.capturedAt, latitude: $0.latitude, longitude: $0.longitude) }
        let rel = shot.bearing.map { LightRead.rel(sunAzimuth: shot.sunAzimuth, heading: $0) }

        caps("Light now").draw(at: CGPoint(x: cx, y: y))
        if let rel, shot.sunElevation > -1 {
            let k = LightClass.of(rel: rel)
            text(k.name, font: mono(11.25)).draw(at: CGPoint(x: cx, y: y + 10))
            text(LightRead.offAxis(rel: rel), font: mono(7.5), color: grey)
                .draw(with: CGRect(x: cx, y: y + 26, width: cw - 70, height: 22), options: .usesLineFragmentOrigin, context: nil)
            plan(rel: rel, hfov: kit.horizontalFOV(focal: shot.lensMM), in: CGRect(x: r.maxX - 63, y: y - 2, width: 63, height: 63))
        } else {
            text(shot.bearing == nil ? "No compass heading" : "Sun down", font: mono(11.25)).draw(at: CGPoint(x: cx, y: y + 10))
            text(shot.bearing == nil ? "This shot was pinned without one." : "No direct sun at this time.", font: mono(7.5), color: grey)
                .draw(with: CGRect(x: cx, y: y + 26, width: cw, height: 22), options: .usesLineFragmentOrigin, context: nil)
        }

        var wy = y + 66
        caps("When to be there").draw(at: CGPoint(x: cx, y: wy))
        wy += 11
        func row(_ label: String, _ value: NSAttributedString, height: CGFloat = 13, strong: Bool = false) {
            hair.setFill()
            UIRectFill(CGRect(x: cx, y: wy, width: cw, height: 0.5))
            text(label, font: mono(7.5), color: strong ? ink : grey).draw(at: CGPoint(x: cx, y: wy + 3))
            value.draw(with: CGRect(x: cx + 42, y: wy + 3, width: cw - 42, height: height), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            wy += height + 4
        }
        let best: LightRead.Best?
        if let day, let heading = shot.bearing {
            best = LightRead.best(day: day, heading: heading)
            if let best {
                let v = NSMutableAttributedString(attributedString: text("\(Format.time(best.start))–\(Format.time(best.end))\n", font: mono(9.75)))
                v.append(text(best.why, font: mono(7.5), color: grey))
                row("Best", v, height: 24, strong: true)
            }
            let recce = NSMutableAttributedString(attributedString: text(Format.time(shot.plannedTime), font: mono(7.5)))
            if let rel { recce.append(text(" · \(LightClass.of(rel: rel).short)", font: mono(7.5), color: grey)) }
            row("Recce", recce)
            for (label, k) in [("Backlit", LightClass.backlit), ("Side lit", .side)] {
                row(label, LightRead.spans(k, day: day, heading: heading).map { text($0, font: mono(7.5)) }
                    ?? text("not from here today", font: mono(7.5), color: grey))
            }
            if let g = LightRead.golden(day) {
                let v = NSMutableAttributedString(attributedString: text("\(Format.time(g.lowerBound))–\(Format.time(g.upperBound))", font: mono(7.5)))
                let mid = g.lowerBound.addingTimeInterval(g.upperBound.timeIntervalSince(g.lowerBound) / 2)
                if let k = LightRead.light(at: mid, day: day, heading: heading) {
                    v.append(text(" · \(k.short)", font: mono(7.5), color: grey))
                }
                row("Golden", v)
            }
        } else {
            best = nil
            text(day == nil ? "No location saved for this shot." : "Needs the compass heading.", font: mono(7.5), color: grey)
                .draw(at: CGPoint(x: cx, y: wy + 3))
        }

        // Spec grid: ten fields, five across.
        y = imgRect.maxY + 9
        let sensorH = kit.mode.widthMM / max(kit.mode.shape, 0.1)
        let sameCamera = kit.camera.name == shot.cameraName
        let shadows = shot.sunElevation > 0 ? String(format: "%.1f× height", 1 / tan(shot.sunElevation * .pi / 180)) : "none"
        let spec: [(String, String)] = [
            ("Camera", shot.cameraName),
            ("Mode", sameCamera ? kit.mode.name : "–"),
            ("Sensor", sameCamera ? String(format: "%.2f × %.2fmm", kit.mode.widthMM, sensorH) : "–"),
            ("Resolution", sameCamera ? kit.camera.resolution : "–"),
            ("Lens", "\(Format.mm(shot.lensMM))mm · \(shot.lensSeries)"),
            ("H. field", "\(Int(kit.horizontalFOV(focal: shot.lensMM).rounded()))°"),
            ("Frame lines", "\(shot.aspect.label) in \(ratioLabel(kit.mode.shape))"),
            ("Heading", shot.bearing.map { Format.bearing($0) } ?? "–"),
            ("Sun", "\(Int(shot.sunAzimuth.rounded()))° · \(Int(shot.sunElevation.rounded()))° up"),
            ("Shadows", shadows),
        ]
        let colW = (r.width + 9) / 5
        for (i, f) in spec.enumerated() {
            let x = r.minX + CGFloat(i % 5) * colW
            let fy = y + CGFloat(i / 5) * 24
            caps(f.0).draw(at: CGPoint(x: x, y: fy))
            text(f.1, font: mono(7.5)).draw(with: CGRect(x: x, y: fy + 9, width: colW - 9, height: 11),
                                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        y += 48 + 6

        // Through the day from here.
        caps("Through the day from here").draw(at: CGPoint(x: r.minX, y: y))
        if let day, let heading = shot.bearing {
            strip(day: day, heading: heading, shotTime: shot.plannedTime, best: best,
                  in: CGRect(x: r.minX, y: y + 9, width: r.width, height: 30))
        } else {
            text("–", font: mono(7.5), color: grey).draw(at: CGPoint(x: r.minX, y: y + 12))
        }
        y += 44

        // Notes, and a QR code that opens directions to the spot.
        let qr: CGFloat = 38
        let qrImage = loc?.directionsURL.flatMap { qrCode($0.absoluteString) }
        let qrLabel = caps("Directions", size: 5.5)
        let notesW = r.width - (qrImage == nil ? 0 : qr + qrLabel.size().width + 22)
        caps("Notes").draw(at: CGPoint(x: r.minX, y: y))
        if let notes = shot.notes, !notes.isEmpty {
            text(notes, font: mono(7.5)).draw(with: CGRect(x: r.minX, y: y + 10, width: notesW, height: 22),
                                              options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        } else {
            // Blank ruled lines to write on.
            hair.setFill()
            UIRectFill(CGRect(x: r.minX, y: y + 20, width: notesW, height: 0.5))
            UIRectFill(CGRect(x: r.minX, y: y + 33, width: notesW, height: 0.5))
        }
        if let qrImage, let url = loc?.directionsURL {
            let box = CGRect(x: r.maxX - qr, y: y - 2, width: qr, height: qr)
            ctx.cgContext.saveGState()
            ctx.cgContext.interpolationQuality = .none
            qrImage.draw(in: box)
            ctx.cgContext.restoreGState()
            ctx.setURL(url, for: box)
            qrLabel.draw(at: CGPoint(x: box.minX - qrLabel.size().width - 6, y: box.maxY - qrLabel.size().height))
        }
    }

    private static func onDayMinutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    /// The day as a timeline anyone can read: hours along the bottom, the sun's height up the
    /// side, golden hour shaded orange, and each shot's number at its planned time.
    private static func dayChart(_ scene: ScoutScene, at loc: ShotLocation, on date: Date, y top: CGFloat) -> CGFloat {
        let day = SunCalculator.day(containing: date, latitude: loc.latitude, longitude: loc.longitude)
        guard let rise = day.sunrise, let set = day.sunset else { return top }
        let cal = Calendar.current
        caps("The day").draw(at: CGPoint(x: pad, y: top))
        let times = scene.shots.map { onDayMinutes($0.plannedTime) }
        var sub = "The sun across the day at this scene's spot: the higher the line, the higher the sun."
        if let a = times.min(), let b = times.max() {
            let span = b - a
            sub += b > a
                ? " Shots from \(hm(a)) to \(hm(b)), \(span / 60 > 0 ? "\(span / 60) h " : "")\(span % 60) min."
                : " All shots at \(hm(a))."
        }
        text(sub, font: mono(7.5), color: grey)
            .draw(with: CGRect(x: pad, y: top + 10, width: page.width - pad * 2, height: 12), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)

        let from = rise.addingTimeInterval(-3600), to = set.addingTimeInterval(3600)
        let span = to.timeIntervalSince(from)
        let plot = CGRect(x: pad, y: top + 62, width: page.width - pad * 2, height: 84)
        let samples = day.samples.filter { $0.time >= from && $0.time <= to }
        let maxEl = max(10, samples.map(\.position.elevation).max() ?? 10)
        let minEl = -10.0
        func x(_ t: Date) -> CGFloat { plot.minX + plot.width * CGFloat(min(max(t.timeIntervalSince(from), 0), span) / span) }
        func y(_ el: Double) -> CGFloat { plot.maxY - plot.height * CGFloat((max(el, minEl) - minEl) / (maxEl - minEl)) }
        func onDay(_ t: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: t)
            return cal.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: rise) ?? t
        }

        // Night and blue hour either side of the day, shaded and named.
        func band(_ a: Date, _ b: Date, _ color: UIColor, _ name: String, _ label: UIColor) {
            guard b > from, a < to else { return }
            let x0 = x(max(a, from)), x1 = x(min(b, to))
            guard x1 - x0 > 1 else { return }
            color.setFill()
            UIRectFill(CGRect(x: x0, y: plot.minY, width: x1 - x0, height: plot.height))
        }
        // Night runs up to the morning blue hour and on from the evening one.
        let amBlue = day.blueWindows.first { $0.upperBound <= rise }
        let pmBlue = day.blueWindows.last { $0.lowerBound >= set }
        band(from, amBlue?.lowerBound ?? rise, ink.withAlphaComponent(0.07), "Night", grey)
        band(pmBlue?.upperBound ?? set, to, ink.withAlphaComponent(0.07), "Night", grey)
        for bw in day.blueWindows {
            band(bw.lowerBound, bw.upperBound, UIColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 0.14), "Blue", grey)
        }

        // Golden hour, shaded the full height and named.
        for g in day.goldenWindows where g.upperBound > from && g.lowerBound < to {
            let gx0 = x(max(g.lowerBound, from)), gx1 = x(min(g.upperBound, to))
            sun.withAlphaComponent(0.12).setFill()
            UIRectFill(CGRect(x: gx0, y: plot.minY, width: gx1 - gx0, height: plot.height))
        }

        // Horizon, with sunrise and sunset on it.
        let hy = y(0)
        rule.setFill()
        UIRectFill(CGRect(x: plot.minX, y: hy, width: plot.width, height: 0.75))
        let r = text("sunrise \(Format.time(rise))", font: mono(6.75), color: grey)
        r.draw(at: CGPoint(x: max(plot.minX, x(rise) - r.size().width / 2), y: hy + 3))
        let st = text("sunset \(Format.time(set))", font: mono(6.75), color: grey)
        st.draw(at: CGPoint(x: min(plot.maxX - st.size().width, x(set) - st.size().width / 2), y: hy + 3))

        // The sun's height.
        let curve = UIBezierPath()
        for (i, s) in samples.enumerated() {
            let p = CGPoint(x: x(s.time), y: y(s.position.elevation))
            if i == 0 { curve.move(to: p) } else { curve.addLine(to: p) }
        }
        ink.withAlphaComponent(0.55).setStroke()
        curve.lineWidth = 1
        curve.stroke()

        // Hours along the bottom.
        let axisY = plot.maxY + 4
        var t = cal.date(bySettingHour: cal.component(.hour, from: from) + 1, minute: 0, second: 0, of: from) ?? from
        while t < to {
            let h = cal.component(.hour, from: t)
            if h % 2 == 0 {
                let l = text(String(format: "%02d:00", h), font: mono(6.75), color: grey)
                l.draw(at: CGPoint(x: x(t) - l.size().width / 2, y: axisY))
                hair.setFill()
                UIRectFill(CGRect(x: x(t) - 0.25, y: plot.maxY - 3, width: 0.5, height: 3))
            }
            t = t.addingTimeInterval(3600)
        }

        // The light's names under the hours, each centred on its stretch with its times, so
        // every band is named and nothing spills out of its colour. Two rows if they'd touch.
        let amBlue = day.blueWindows.first { $0.upperBound <= rise.addingTimeInterval(3600) }
        let pmBlue = day.blueWindows.last { $0.lowerBound >= set.addingTimeInterval(-3600) }
        let amGold = day.goldenWindows.first { $0.lowerBound <= rise.addingTimeInterval(3600) }
        let pmGold = day.goldenWindows.last { $0.upperBound >= set.addingTimeInterval(-3600) }
        let blueInk = UIColor(red: 0.30, green: 0.40, blue: 0.70, alpha: 1)
        var phases: [(name: String, range: ClosedRange<Date>, color: UIColor)] = []
        if let b = amBlue { phases.append(("Blue hour", b, blueInk)) }
        if let g = amGold { phases.append(("Golden hour", g, sun)) }
        let dayStart = amGold?.upperBound ?? rise, dayEnd = pmGold?.lowerBound ?? set
        if dayEnd > dayStart { phases.append(("Daylight", dayStart...dayEnd, grey)) }
        if let g = pmGold { phases.append(("Golden hour", g, sun)) }
        if let b = pmBlue { phases.append(("Blue hour", b, blueInk)) }
        var rowEnds: [CGFloat] = [-.infinity, -.infinity]
        let phaseY = axisY + 12
        for p in phases {
            let l = NSMutableAttributedString(attributedString: caps(p.name, size: 5.5, color: p.color))
            l.append(text(" " + Format.time(p.range.lowerBound) + "–" + Format.time(p.range.upperBound), font: mono(6), color: grey))
            let lw = l.size().width
            let cx = (x(max(p.range.lowerBound, from)) + x(min(p.range.upperBound, to))) / 2
            let lx = min(max(cx - lw / 2, plot.minX), plot.maxX - lw)
            let row = rowEnds.firstIndex { $0 + 6 < lx } ?? 1
            rowEnds[row] = lx + lw
            l.draw(at: CGPoint(x: lx, y: phaseY + CGFloat(row) * 10))
        }

        // Shots at its planned time: a dot on the sun, and a label in a lane above the chart
        // with a hairline down to it. Shots within a few minutes share one label, and labels
        // that would touch move to the next lane, so they never pile up.
        let timed = scene.shots.map { (shot: $0, when: onDay($0.plannedTime)) }.sorted { $0.when < $1.when }
        var groups: [[(shot: Shot, when: Date)]] = []
        for item in timed {
            if let last = groups.last?.last, x(item.when) - x(last.when) < 10 {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }
        var laneEnds: [CGFloat] = [-.infinity, -.infinity, -.infinity]
        let laneY: [CGFloat] = [top + 25, top + 34, top + 43]
        for g in groups {
            let first = g[0], last = g[g.count - 1]
            let px = (x(first.when) + x(last.when)) / 2
            for item in g {
                let dx = x(item.when), dy = y(LightRead.elevation(at: item.when, day))
                sun.setFill()
                UIBezierPath(ovalIn: CGRect(x: dx - 2.5, y: dy - 2.5, width: 5, height: 5)).fill()
            }
            let ids = g.map(\.shot.number)
            let name = ids.count <= 3 ? ids.joined(separator: " ") : "\(ids[0])–\(ids[ids.count - 1]) (\(ids.count))"
            let time = Format.time(first.when) + (g.count > 1 && Format.time(last.when) != Format.time(first.when) ? "–" + Format.time(last.when) : "")
            let l = NSMutableAttributedString(attributedString: text(name + " ", font: mono(7)))
            l.append(text(time, font: mono(6.5), color: grey))
            let lw = l.size().width
            let lx = min(max(px - lw / 2, plot.minX), plot.maxX - lw)
            let lane = laneEnds.firstIndex { $0 + 6 < lx } ?? laneEnds.indices.min { laneEnds[$0] < laneEnds[$1] }!
            laneEnds[lane] = lx + lw
            let ly = laneY[lane]
            l.draw(at: CGPoint(x: lx, y: ly))
            // The hairline from the label to the highest dot of its group.
            let topDot = g.map { y(LightRead.elevation(at: $0.when, day)) }.min() ?? plot.maxY
            hair.setFill()
            UIRectFill(CGRect(x: px - 0.25, y: ly + 10, width: 0.5, height: max(0, topDot - ly - 12)))
        }
        return axisY + 12 + 20
    }

    /// Seven days across the page: the day, the sky in words, high/low, rain and sun hours.
    private static func weatherStrip(_ days: [DayForecast], y top: CGFloat) -> CGFloat {
        caps("Weather, next \(days.count) days").draw(at: CGPoint(x: pad, y: top))
        let colW = (page.width - pad * 2) / CGFloat(days.count)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE d"
        for (i, d) in days.enumerated() {
            let x = pad + CGFloat(i) * colW
            let y = top + 12
            hair.setFill()
            UIRectFill(CGRect(x: x, y: y, width: colW - 6, height: 0.5))
            text(f.string(from: d.date), font: mono(7.5)).draw(at: CGPoint(x: x, y: y + 3))
            text(d.summary, font: mono(7.5), color: d.code >= 51 ? ink : grey)
                .draw(with: CGRect(x: x, y: y + 13, width: colW - 8, height: 10), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            text("\(Int(d.tempMax.rounded()))°/\(Int(d.tempMin.rounded()))° · \(d.rain)%", font: mono(6.75), color: grey)
                .draw(at: CGPoint(x: x, y: y + 23))
        }
        let credit = text(Forecast.provider.credit, font: mono(5.5), color: grey)
        credit.draw(at: CGPoint(x: page.width - pad - credit.size().width, y: top))
        return top + 12 + 34
    }

    /// A quiet map of the scene with each shot's camera as a dot, its field of view as a cone
    /// (heading and lens width), and its number. False when the map can't be fetched (offline).
    private static func shotMap(_ scene: ScoutScene, around fallback: ShotLocation, kit: Kit, in rect: CGRect,
                                ctx: UIGraphicsPDFRendererContext) -> Bool {
        let places = scene.shots.compactMap(\.location) + [fallback]
        let lats = places.map(\.latitude), lons = places.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        // At least ~300m across, so a single spot still shows its streets.
        let latSpan = max((lats.max()! - lats.min()!) * 1.6, 0.0027 * Double(rect.height / rect.width))
        let lonSpan = max((lons.max()! - lons.min()!) * 1.6, 0.0027 / max(cos(center.latitude * .pi / 180), 0.2))
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        opts.size = rect.size
        opts.scale = 2
        opts.mapType = .mutedStandard
        opts.pointOfInterestFilter = .excludingAll
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        var shot: MKMapSnapshotter.Snapshot?
        let done = DispatchSemaphore(value: 0)
        MKMapSnapshotter(options: opts).start(with: .global(qos: .userInitiated)) { snap, _ in
            shot = snap
            done.signal()
        }
        guard done.wait(timeout: .now() + 10) == .success, let snap = shot else { return false }

        snap.image.draw(in: rect)
        hair.setStroke()
        UIBezierPath(rect: rect).stroke()
        let cg = ctx.cgContext
        cg.saveGState()
        UIRectClip(rect)
        // Cones first, light, so the dots and numbers sit on top.
        var spots: [(at: CGPoint, numbers: [String])] = []
        for s in scene.shots {
            guard let l = s.location else { continue }
            let p0 = snap.point(for: CLLocationCoordinate2D(latitude: l.latitude, longitude: l.longitude))
            let p = CGPoint(x: rect.minX + p0.x, y: rect.minY + p0.y)
            if let b = s.bearing {
                // North is up; a heading turns clockwise from it.
                let half = kit.horizontalFOV(focal: s.lensMM) / 2
                let a0 = (b - half - 90) * .pi / 180, a1 = (b + half - 90) * .pi / 180
                let cone = UIBezierPath()
                cone.move(to: p)
                cone.addArc(withCenter: p, radius: 24, startAngle: a0, endAngle: a1, clockwise: true)
                cone.close()
                ink.withAlphaComponent(0.07).setFill()
                cone.fill()
                ink.withAlphaComponent(0.3).setStroke()
                cone.lineWidth = 0.5
                cone.stroke()
            }
            // Shots taken from the same spot share one pin.
            if let i = spots.firstIndex(where: { hypot($0.at.x - p.x, $0.at.y - p.y) < 12 }) {
                spots[i].numbers.append(s.number)
            } else {
                spots.append((p, [s.number]))
            }
        }
        for spot in spots {
            let p = spot.at
            ink.setFill()
            UIBezierPath(ovalIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)).fill()
            let n = spot.numbers
            let label = n.count <= 3 ? n.joined(separator: " ") : "\(n[0])–\(n[n.count - 1]) (\(n.count))"
            let t = text(label, font: mono(7))
            let tp = CGPoint(x: min(p.x + 5, rect.maxX - t.size().width - 3), y: p.y - t.size().height / 2)
            UIColor.white.withAlphaComponent(0.85).setFill()
            UIRectFill(CGRect(origin: tp, size: t.size()).insetBy(dx: -2, dy: 0))
            t.draw(at: tp)
        }
        cg.restoreGState()
        // North, bottom right.
        let n = text("N ↑", font: mono(7))
        UIColor.white.withAlphaComponent(0.8).setFill()
        let np = CGPoint(x: rect.maxX - n.size().width - 6, y: rect.maxY - n.size().height - 5)
        UIRectFill(CGRect(origin: np, size: n.size()).insetBy(dx: -2, dy: -1))
        n.draw(at: np)
        return true
    }

    /// A crisp black-on-white QR code for a link.
    private static func qrCode(_ s: String) -> UIImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(s.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// Top-down: the camera in the middle facing up, its field of view, the sun on the ring,
    /// and the shadow falling away from it.
    private static func plan(rel: Double, hfov: Double, in box: CGRect) {
        let c = CGPoint(x: box.midX, y: box.midY + 2)
        let R = box.width * 0.38
        let f = hfov / 2 * .pi / 180
        let a = rel * .pi / 180
        let ring = UIBezierPath(ovalIn: CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
        hair.setStroke()
        ring.lineWidth = 0.75
        ring.stroke()
        // The field of view: up is where the lens points.
        let wedge = UIBezierPath()
        wedge.move(to: c)
        wedge.addArc(withCenter: c, radius: R, startAngle: -.pi / 2 - f, endAngle: -.pi / 2 + f, clockwise: true)
        wedge.close()
        ink.withAlphaComponent(0.08).setFill()
        wedge.fill()
        ink.withAlphaComponent(0.5).setStroke()
        wedge.lineWidth = 0.5
        wedge.stroke()
        // The camera.
        ink.setFill()
        UIRectFill(CGRect(x: c.x - 3.5, y: c.y - 2, width: 7, height: 5))
        let nose = UIBezierPath()
        nose.move(to: CGPoint(x: c.x - 2, y: c.y - 2))
        nose.addLine(to: CGPoint(x: c.x, y: c.y - 5.5))
        nose.addLine(to: CGPoint(x: c.x + 2, y: c.y - 2))
        nose.close()
        nose.fill()
        // The sun, and the shadow line away from it.
        let s = CGPoint(x: c.x + R * sin(a), y: c.y - R * cos(a))
        let shadow = UIBezierPath()
        shadow.move(to: c)
        shadow.addLine(to: CGPoint(x: 2 * c.x - s.x, y: 2 * c.y - s.y))
        shadow.setLineDash([1.5, 1.5], count: 2, phase: 0)
        shadow.lineWidth = 0.75
        ink.withAlphaComponent(0.35).setStroke()
        shadow.stroke()
        sun.setFill()
        UIBezierPath(ovalIn: CGRect(x: s.x - 3.5, y: s.y - 3.5, width: 7, height: 7)).fill()
        let lens = text("LENS", font: mono(5), color: grey)
        lens.draw(at: CGPoint(x: c.x - lens.size().width / 2, y: box.minY))
    }

    /// The day for this heading, sunrise to sunset: light classes darkest (backlit) to
    /// lightest (front lit), golden hour as an orange bar, the shot time as an orange tick,
    /// the best time as a black bar underneath.
    private static func strip(day: SunDay, heading: Double, shotTime: Date, best: LightRead.Best?, in box: CGRect) {
        guard let rise = day.sunrise, let set = day.sunset, set > rise else { return }
        let span = set.timeIntervalSince(rise)
        func x(_ t: Date) -> CGFloat { box.minX + box.width * CGFloat(min(max(t.timeIntervalSince(rise), 0), span) / span) }
        let shades: [CGFloat] = [0.82, 0.55, 0.32, 0.16, 0.06]
        for w in LightRead.windows(day: day, heading: heading) {
            let rect = CGRect(x: x(w.start), y: box.minY + 6, width: max(0.75, x(w.end) - x(w.start)), height: 10.5)
            ink.withAlphaComponent(shades[w.light.rawValue]).setFill()
            UIRectFill(rect)
            if rect.width > 20 {
                text(w.light.letter, font: mono(5.6), color: w.light.rawValue < 2 ? UIColor(white: 0.95, alpha: 1) : ink)
                    .draw(at: CGPoint(x: rect.minX + 3, y: rect.minY + 2.5))
            }
        }
        if let g = LightRead.golden(day) {
            sun.setFill()
            UIRectFill(CGRect(x: x(g.lowerBound), y: box.minY + 3, width: max(1, x(min(g.upperBound, set)) - x(g.lowerBound)), height: 1.5))
        }
        // The shot's time on the recce day.
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: shotTime)
        if let t = cal.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: rise) {
            sun.setFill()
            UIRectFill(CGRect(x: x(t) - 0.5, y: box.minY + 1.5, width: 1, height: 18))
        }
        if let best {
            ink.setFill()
            UIRectFill(CGRect(x: x(best.start), y: box.minY + 18, width: max(1.5, x(best.end) - x(best.start)), height: 1.5))
        }
        var labels: [(Date, String)] = [(rise, Format.time(rise))]
        for h in [9, 12, 15] {
            if let t = cal.date(bySettingHour: h, minute: 0, second: 0, of: rise), t > rise, t < set {
                labels.append((t, String(format: "%02d", h)))
            }
        }
        labels.append((set, Format.time(set)))
        for (i, l) in labels.enumerated() {
            let t = text(l.1, font: mono(5.6), color: grey)
            let w = t.size().width
            let lx = i == 0 ? x(l.0) : i == labels.count - 1 ? x(l.0) - w : x(l.0) - w / 2
            t.draw(at: CGPoint(x: lx, y: box.minY + 21))
        }
    }

    /// 1.78 → "16:9"
    static func ratioLabel(_ shape: Double) -> String {
        let known: [(Double, String)] = [(16.0 / 9, "16:9"), (17.0 / 9, "17:9"), (1.5, "3:2"), (4.0 / 3, "4:3"),
                                         (2, "2:1"), (1.66, "1.66"), (2.39, "2.39"), (1.85, "1.85"), (1.37, "1.37")]
        if let k = known.first(where: { abs($0.0 - shape) < 0.015 }) { return k.1 }
        return String(format: "%.2f", shape)
    }

    // MARK: Photos only: the frames two across, the shot ID and scene under each

    static func photosPDF(project: Project, scenes: [ScoutScene]) -> Data {
        let shots = scenes.flatMap { sc in sc.shots.map { ($0, sc) } }
        let p: CGFloat = 36
        let gap: CGFloat = 12
        let cellW = (page.width - p * 2 - gap) / 2
        let imgH: CGFloat = 147
        let cellH = imgH + 6 + 12 + 21
        let top = p + 24 + 6
        let rows = max(1, Int((page.height - top - p - 20 + 21) / cellH))
        let perPage = rows * 2
        let pages = max(1, Int(ceil(Double(shots.count) / Double(perPage))))
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { ctx in
            for pg in 0..<pages {
                ctx.beginPage()
                wordmark(at: CGPoint(x: p, y: p), size: 10)
                let k = caps(project.name)
                k.draw(at: CGPoint(x: page.width - p - k.size().width, y: p + 1))
                for (i, item) in shots.dropFirst(pg * perPage).prefix(perPage).enumerated() {
                    let x = p + CGFloat(i % 2) * (cellW + gap)
                    let y = top + CGFloat(i / 2) * cellH
                    let rect = CGRect(x: x, y: y, width: cellW, height: imgH)
                    if let image = ThumbCache.full(for: item.0).flatMap({ printable($0, for: rect) }) {
                        ctx.cgContext.saveGState()
                        UIRectClip(rect)
                        let crop = fitCrop(aspect: item.0.aspect.value, in: image.size)
                        image.draw(in: aspectFill(crop: crop, imageSize: image.size, in: rect))
                        ctx.cgContext.restoreGState()
                    } else {
                        UIColor(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1).setFill()
                        UIRectFill(rect)
                    }
                    text(item.0.number, font: mono(8.25)).draw(at: CGPoint(x: x, y: rect.maxY + 5))
                    let s = text(item.1.name, font: mono(8.25), color: grey)
                    s.draw(with: CGRect(x: x + cellW - min(s.size().width, cellW - 40), y: rect.maxY + 5, width: min(s.size().width, cellW - 40), height: 12),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
                }
                if shots.isEmpty {
                    text("No shots yet.", font: mono(9), color: grey).draw(at: CGPoint(x: p, y: top))
                }
                let fy = page.height - p - 8
                text(ShotListView.shots(shots.count), font: mono(6.75), color: grey).draw(at: CGPoint(x: p, y: fy))
                let n = text("\(pg + 1) / \(pages)", font: mono(6.75), color: grey)
                n.draw(at: CGPoint(x: page.width - p - n.size().width, y: fy))
            }
        }
    }
}
