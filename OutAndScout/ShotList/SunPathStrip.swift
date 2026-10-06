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
            Text(" · " + ([s.lightRead, s.sunElevation > -1 ? "\(Int(s.sunElevation.rounded()))° up" : "sun down"]
                .compactMap { $0 }.joined(separator: " · ")))
                .foregroundStyle(Sheet.muted)
        }
        .font(.osDataSmall)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
        let from = rise.addingTimeInterval(-45 * 60), to = set.addingTimeInterval(45 * 60)
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
            let w = geo.size.width, h = geo.size.height - 12
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

                Text(Format.time(rise)).fixedSize().position(x: max(x(rise), 14), y: h + 7)
                Text(Format.time(set)).fixedSize().position(x: min(x(set), w - 14), y: h + 7)
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
}

extension Shot {
    /// How the sun falls on the shot from the way the camera faced: "¾ back, sun left",
    /// "backlit", "front lit". Nil without a compass heading or once the sun is down.
    var lightClass: LightClass? {
        guard let bearing, sunElevation > -1 else { return nil }
        return LightClass.of(rel: LightRead.rel(sunAzimuth: sunAzimuth, heading: bearing))
    }

    var lightRead: String? {
        guard let k = lightClass, let bearing else { return nil }
        if k == .backlit || k == .front { return k.short }
        let rel = LightRead.rel(sunAzimuth: sunAzimuth, heading: bearing)
        return "\(k.short), sun \(rel > 0 ? "right" : "left")"
    }
}
