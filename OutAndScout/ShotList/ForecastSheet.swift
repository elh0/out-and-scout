import SwiftUI

/// The next two weeks for a scene's spot: the sky in words, rain, sun hours, wind and
/// temperature, and the cloud at each shot's time with what it does to the light.
/// Off until turned on, since it sends the spot (rounded to about 1 km) to a weather service.
struct ForecastSheet: View {
    let sceneName: String
    let place: ShotLocation
    let shots: [Shot]
    let onDone: () -> Void

    @AppStorage(Forecast.optInKey) private var allowed = false
    @State private var days: [DayForecast] = []
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            PanelHeader(title: "Weather · \(sceneName)", sub: place.label ?? "Next 14 days at this spot", action: ("Done", onDone))

            if !allowed {
                optIn
            } else if loading && days.isEmpty {
                Text("Getting the forecast…").font(.osRow).foregroundStyle(Sheet.muted)
            } else if failed && days.isEmpty {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Couldn't get the forecast. Check your signal and try again.").font(.osRow).foregroundStyle(Sheet.muted)
                    Button("Try again") { Task { await load() } }.buttonStyle(PillButtonStyle(kind: .outline)).frame(maxWidth: 200)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(days) { row($0) }
                    }
                }
                HStack {
                    Text(Forecast.provider.credit).font(.osDataSmall).foregroundStyle(Sheet.muted)
                    Spacer()
                    Button("Turn off forecasts") { allowed = false; days = [] }
                        .font(.osDataSmall).foregroundStyle(Sheet.muted).buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.horizontal, 20)
        .background(Sheet.bg)
        .foregroundStyle(Sheet.text)
        .font(.osRow)
        .task(id: allowed) { if allowed { await load() } }
    }

    private var optIn: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("See the next 14 days here: cloud, rain, sun hours and wind, and the cloud at each shot's time.")
                .font(.osRow)
            Text("This sends the scene's rough location (to about 1 km) to a weather service. Nothing else: no name, account or phone id.")
                .font(.osData).foregroundStyle(Sheet.muted)
            Button("Turn on weather forecasts") { allowed = true }
                .buttonStyle(PillButtonStyle(kind: .outline))
                .frame(maxWidth: 280)
        }
    }

    private func load() async {
        loading = true
        failed = false
        do {
            days = try await Forecast.days(latitude: place.latitude, longitude: place.longitude)
        } catch {
            failed = true
        }
        loading = false
    }

    /// Distinct shot times in this scene, "08:30", "19:10".
    private var shotTimes: [(label: String, time: Date)] {
        var seen = Set<String>()
        return shots.sorted { Self.minutes($0.plannedTime) < Self.minutes($1.plannedTime) }.compactMap { s in
            let l = Format.time(s.plannedTime)
            return seen.insert(l).inserted ? (l, s.plannedTime) : nil
        }
    }

    private static func minutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func row(_ d: DayForecast) -> some View {
        let day = d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let atShots = shotTimes.prefix(4).compactMap { t -> String? in
            guard let c = d.cloud(at: t.time) else { return nil }
            return "\(t.label) \(c)% \(DayForecast.light(cloud: c))"
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(day).frame(width: 96, alignment: .leading)
                Text(d.summary).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(Int(d.tempMax.rounded()))° / \(Int(d.tempMin.rounded()))°").font(.osNum)
            }
            .lineLimit(1)
            Text((["rain \(d.rain)%", String(format: "sun %.1fh", d.sunHours), "wind \(Int(d.wind.rounded())) km/h"]
                  + (atShots.isEmpty ? [] : ["cloud at your shots: " + atShots.joined(separator: ", ")])).joined(separator: " · "))
                .font(.osDataSmall).foregroundStyle(Sheet.muted)
                .lineLimit(2)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rule() }
    }
}
