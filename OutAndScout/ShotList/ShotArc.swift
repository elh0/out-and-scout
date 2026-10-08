import SwiftUI

/// The shot list's thin sun arc (round 4): sunrise to sunset as a dotted line, golden hour
/// in orange, every shot as a dot at its time, the open one bigger and orange with its
/// number and time. Tap a dot to open that shot.
struct ShotArc: View {
    let shots: [Shot]
    let selected: UUID?
    var pick: (Shot) -> Void = { _ in }

    var body: some View {
        if let day {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let rise = day.sunrise!, set = day.sunset!
                let pad: CGFloat = 40
                let span = set.timeIntervalSince(rise)
                let top = max(10, day.samples.map(\.position.elevation).max() ?? 10)
                let base = h - 8
                let x = { (t: Date) in pad + CGFloat(min(max(t.timeIntervalSince(rise) / span, 0), 1)) * (w - pad * 2) }
                let y = { (el: Double) in base - CGFloat(max(el, 0) / top) * (base - 12) }
                let samples = day.samples.filter { $0.time >= rise && $0.time <= set }
                let dots = shots.map { s -> Dot in
                    let t = onDay(s.plannedTime, rise)
                    return Dot(shot: s, at: CGPoint(x: x(t), y: y(LightRead.elevation(at: t, day))))
                }

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        var line = Path()
                        line.move(to: CGPoint(x: pad, y: base))
                        line.addLine(to: CGPoint(x: w - pad, y: base))
                        ctx.stroke(line, with: .color(Sheet.text.opacity(0.2)), lineWidth: 1)

                        var arc = Path()
                        for (i, s) in samples.enumerated() {
                            let p = CGPoint(x: x(s.time), y: y(s.position.elevation))
                            if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
                        }
                        ctx.stroke(arc, with: .color(Sheet.text.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

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

                    Text(Format.time(rise)).font(Fonts.mono(8)).foregroundStyle(Sheet.muted)
                        .fixedSize().position(x: pad / 2 - 2, y: base)
                    Text(Format.time(set)).font(Fonts.mono(8)).foregroundStyle(Sheet.muted)
                        .fixedSize().position(x: w - pad / 2 + 2, y: base)

                    ForEach(dots.filter { $0.id != selected }) { d in
                        Circle().fill(Sheet.text.opacity(0.85)).frame(width: 5.5, height: 5.5).position(d.at)
                    }
                    if let d = dots.first(where: { $0.id == selected }) {
                        Circle().fill(Palette.sun).frame(width: 10, height: 10).position(d.at)
                        Text("\(d.shot.number) · \(Format.time(d.shot.plannedTime))")
                            .font(Fonts.mono(8)).foregroundStyle(Sheet.text)
                            .fixedSize()
                            .position(x: min(max(d.at.x, 30), w - 30), y: max(d.at.y - 11, 4))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { at in
                    let dist = { (p: CGPoint) in hypot(p.x - at.x, p.y - at.y) }
                    if let near = dots.min(by: { dist($0.at) < dist($1.at) }), dist(near.at) < 30 { pick(near.shot) }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("the day's sun, \(shots.count) shots on it")
        } else {
            Color.clear
        }
    }

    private struct Dot: Identifiable {
        let shot: Shot
        let at: CGPoint
        var id: UUID { shot.id }
    }

    /// The open shot's day and place, else the first shot with a place.
    private var day: SunDay? {
        let anchor = shots.first { $0.id == selected && $0.location != nil } ?? shots.first { $0.location != nil }
        guard let anchor, let loc = anchor.location else { return nil }
        let d = SunCalculator.day(containing: anchor.capturedAt, latitude: loc.latitude, longitude: loc.longitude)
        return d.sunrise == nil || d.sunset == nil ? nil : d
    }

    private func onDay(_ t: Date, _ rise: Date) -> Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(bySettingHour: c.hour ?? 12, minute: c.minute ?? 0, second: 0, of: rise) ?? t
    }
}
