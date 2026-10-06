import SwiftUI

/// The scene's day on the Shot List (Elliot, 6 Oct 2026): the sun's arc from sunrise to
/// sunset, golden hour in orange, and every shot as a dot where the sun was for it.
/// The picked shot is the orange one, with its light read beside the arc. Tap a dot to pick it.
struct SunPathStrip: View {
    let shots: [Shot]
    let selected: Shot?
    var height: CGFloat = 58
    var pick: (Shot) -> Void = { _ in }

    var body: some View {
        if let day {
            VStack(alignment: .leading, spacing: 4) {
                if let s = selected { caption(s) }
                arc(day)
                    .frame(height: height)
                times(day)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("No location saved, so no sun path.")
                .font(.osDataSmall)
                .foregroundStyle(Sheet.muted)
        }
    }

    /// "1A · 19:12 · ¾ back, sun left · 6° up"
    private func caption(_ s: Shot) -> some View {
        HStack(spacing: 0) {
            Text(s.number + " · " + Format.time(s.plannedTime)).foregroundStyle(Palette.sun)
            Text(" · " + ([s.lightRead, s.sunElevation > -1 ? "\(Int(s.sunElevation.rounded()))° up" : "sun down", lasts(s)]
                .compactMap { $0 }.joined(separator: " · ")))
                .foregroundStyle(Sheet.muted)
        }
        .font(.osDataSmall)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "same light till 19:40": when the sun leaves this side of the frame, from the shot's heading.
    private func lasts(_ s: Shot) -> String? {
        guard let day, let b = s.bearing, s.sunElevation > -1 else { return nil }
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: s.plannedTime)
        guard let rise = day.sunrise,
              let t = cal.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: rise),
              let w = LightRead.windows(day: day, heading: b).first(where: { $0.start <= t && $0.end >= t }) else { return nil }
        return "same light till \(Format.time(w.end))"
    }

    /// The selected shot's day and place, else the first shot with a place.
    private var day: SunDay? {
        guard let anchor = (selected?.location != nil ? selected : nil) ?? shots.first(where: { $0.location != nil }),
              let loc = anchor.location else { return nil }
        let d = SunCalculator.day(containing: anchor.capturedAt, latitude: loc.latitude, longitude: loc.longitude)
        return d.sunrise == nil || d.sunset == nil ? nil : d
    }

    private struct Dot: Identifiable {
        let shot: Shot
        let at: CGPoint
        var id: UUID { shot.id }
    }

    private func arc(_ day: SunDay) -> some View {
        let rise = day.sunrise!, set = day.sunset!
        let amBlue = day.blueWindows.first { $0.upperBound <= rise.addingTimeInterval(3600) }
        let pmBlue = day.blueWindows.last { $0.lowerBound >= set.addingTimeInterval(-3600) }
        let from = (amBlue?.lowerBound ?? rise.addingTimeInterval(-40 * 60)).addingTimeInterval(-15 * 60)
        let to = (pmBlue?.upperBound ?? set.addingTimeInterval(40 * 60)).addingTimeInterval(15 * 60)
        let samples = day.samples.filter { $0.time >= from && $0.time <= to }
        let top = max(10, samples.map(\.position.elevation).max() ?? 10)
        let low = -8.0
        let cal = Calendar.current

        /// A shot's planned time on this day.
        func onDay(_ t: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute], from: t)
            return cal.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: rise) ?? t
        }

        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height - 2
            let span = to.timeIntervalSince(from)
            let x = { (t: Date) in CGFloat(min(max(t.timeIntervalSince(from), 0), span) / span) * w }
            let y = { (el: Double) in CGFloat((top - max(el, low)) / (top - low)) * h }
            let horizon = y(0)
            let dots: [Dot] = shots.map { s in
                let t = onDay(s.plannedTime)
                return Dot(shot: s, at: CGPoint(x: x(t), y: y(LightRead.elevation(at: t, day))))
            }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    // Dawn and dusk (blue hour), shaded behind the arc.
                    for b in [amBlue, pmBlue].compactMap({ $0 }) {
                        let r = CGRect(x: x(b.lowerBound), y: 0, width: max(1, x(b.upperBound) - x(b.lowerBound)), height: h)
                        ctx.fill(Path(r), with: .color(Self.blue.opacity(0.22)))
                    }
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: horizon))
                    line.addLine(to: CGPoint(x: w, y: horizon))
                    ctx.stroke(line, with: .color(Sheet.rule), lineWidth: 1)

                    var path = Path()
                    for (i, s) in samples.enumerated() {
                        let p = CGPoint(x: x(s.time), y: y(s.position.elevation))
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    ctx.stroke(path, with: .color(Sheet.muted.opacity(0.7)), lineWidth: 1)

                    for g in day.goldenWindows {
                        var gold = Path()
                        var started = false
                        for s in samples where g.contains(s.time) {
                            let p = CGPoint(x: x(s.time), y: y(s.position.elevation))
                            if started { gold.addLine(to: p) } else { gold.move(to: p); started = true }
                        }
                        ctx.stroke(gold, with: .color(Palette.sun), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }

                ForEach(dots.filter { $0.id != selected?.id }) { d in
                    Circle().fill(Sheet.text.opacity(0.75)).frame(width: 6, height: 6).position(d.at)
                }
                if let s = selected, let p = dots.first(where: { $0.id == s.id })?.at {
                    Circle().fill(Palette.sun).frame(width: 10, height: 10)
                        .background(Circle().fill(Palette.sun.opacity(0.18)).frame(width: 18, height: 18))
                        .position(p)
                }

            }
            .font(.osNumTiny)
            .foregroundStyle(Sheet.muted)
            .contentShape(Rectangle())
            .onTapGesture { at in
                let d = { (dot: Dot) in hypot(dot.at.x - at.x, dot.at.y - at.y) }
                if let near = dots.min(by: { d($0) < d($1) }), d(near) < 30 {
                    pick(near.shot)
                }
            }
        }
        .accessibilityLabel("sun path, sunrise \(Format.time(rise)), sunset \(Format.time(set))")
    }

    static let blue = Color(hex: 0x5A73BF)

    /// The light's names and times, each under its own part of the arc (Elliot, 6 Oct 2026):
    /// morning ones start where their band starts, evening ones end where theirs ends,
    /// one per line so they never run into each other.
    private func times(_ day: SunDay) -> some View {
        let rise = day.sunrise!, set = day.sunset!
        let amBlue = day.blueWindows.first { $0.upperBound <= rise.addingTimeInterval(3600) }
        let pmBlue = day.blueWindows.last { $0.lowerBound >= set.addingTimeInterval(-3600) }
        let amGold = day.goldenWindows.first { $0.lowerBound <= rise.addingTimeInterval(3600) }
        let pmGold = day.goldenWindows.last { $0.upperBound >= set.addingTimeInterval(-3600) }
        let from = (amBlue?.lowerBound ?? rise.addingTimeInterval(-40 * 60)).addingTimeInterval(-15 * 60)
        let to = (pmBlue?.upperBound ?? set.addingTimeInterval(40 * 60)).addingTimeInterval(15 * 60)

        struct Label: Identifiable {
            let id: Int
            let text: Text
            let at: Date
            let morning: Bool
        }
        func item(_ name: String, _ t: Date?, _ color: Color = Sheet.muted) -> Text? {
            guard let t else { return nil }
            return Text(name + " ").foregroundColor(color) + Text(Format.time(t)).foregroundColor(Sheet.text)
        }
        let morning: [(Text?, Date?)] = [
            (item("Blue hour", amBlue?.lowerBound, Self.blue), amBlue?.lowerBound),
            (item("Sunrise", rise), rise),
            (item("Golden hour till", amGold?.upperBound, Palette.sun), amGold?.lowerBound),
        ]
        let evening: [(Text?, Date?)] = [
            (item("Golden hour", pmGold?.lowerBound, Palette.sun), pmGold?.upperBound),
            (item("Sunset", set), set),
            (item("Blue hour till", pmBlue?.upperBound, Self.blue), pmBlue?.upperBound),
        ]
        var labels: [Label] = []
        for (i, m) in morning.enumerated() { if let t = m.0, let at = m.1 { labels.append(Label(id: i, text: t, at: at, morning: true)) } }
        for (i, e) in evening.enumerated() { if let t = e.0, let at = e.1 { labels.append(Label(id: 10 + i, text: t, at: at, morning: false)) } }
        let line: CGFloat = 13

        return GeometryReader { geo in
            let w = geo.size.width
            let span = to.timeIntervalSince(from)
            let x = { (t: Date) in CGFloat(min(max(t.timeIntervalSince(from), 0), span) / span) * w }
            ZStack(alignment: .topLeading) {
                // Pins the stack to the strip's full width, so the guides measure from its left edge.
                Color.clear.frame(width: w, height: line * 3)
                ForEach(labels) { l in
                    let row = CGFloat(l.id % 10)
                    l.text
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            l.morning ? -min(x(l.at), w - d.width) : -max(0, min(x(l.at), w) - d.width)
                        }
                        .alignmentGuide(.top) { _ in -row * line }
                }
            }
        }
        .frame(height: line * 3)
        .font(.osNumTiny)
        .lineLimit(1)
    }
}

extension LightClass {
    /// "¾ back, sun left", "backlit", "front lit": the sun relative to where the lens points.
    static func read(rel: Double) -> String {
        let k = of(rel: rel)
        if k == .backlit || k == .front { return k.short }
        return "\(k.short), sun \(rel > 0 ? "right" : "left")"
    }
}

extension Shot {
    /// How the sun falls on the shot from the way the camera faced: "¾ back, sun left",
    /// "backlit", "front lit". Nil without a compass heading or once the sun is down.
    var lightClass: LightClass? {
        guard let bearing, sunElevation > -1 else { return nil }
        return LightClass.of(rel: LightRead.rel(sunAzimuth: sunAzimuth, heading: bearing))
    }

    var lightRead: String? {
        guard lightClass != nil, let bearing else { return nil }
        return LightClass.read(rel: LightRead.rel(sunAzimuth: sunAzimuth, heading: bearing))
    }
}
