import Foundation

/// One day of weather for a scene's spot (Elliot, 6 Oct 2026: recces are usually a week
/// out, sometimes two).
struct DayForecast: Codable, Identifiable, Hashable {
    var date: Date
    var code: Int
    var tempMax: Double
    var tempMin: Double
    /// Highest chance of rain in the day, %.
    var rain: Int
    var sunHours: Double
    /// km/h
    var wind: Double
    /// Cloud cover % for each hour, 0–23.
    var hourlyCloud: [Int]
    var id: Date { date }

    /// "Overcast", "Partly cloudy", "Showers"
    var summary: String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunder"
        default: return "Mixed"
        }
    }

    func cloud(at time: Date) -> Int? {
        let h = Calendar.current.component(.hour, from: time)
        return hourlyCloud.indices.contains(h) ? hourlyCloud[h] : nil
    }

    /// What the cloud does to the light: "hard sun", "broken cloud", "soft, overcast".
    static func light(cloud: Int) -> String {
        cloud < 25 ? "hard sun" : cloud < 70 ? "broken cloud" : "soft, overcast"
    }
}

/// Where forecasts come from. Open-Meteo while testing; Apple WeatherKit for release, once
/// the paid developer account is live (Open-Meteo's free tier is non-commercial only).
protocol ForecastProvider {
    /// "Open-Meteo", shown as the credit under the forecast.
    var credit: String { get }
    func days(latitude: Double, longitude: Double) async throws -> [DayForecast]
}

/// Only the spot, rounded to about 1 km, is sent. No account, device or user id.
enum Forecast {
    static var provider: ForecastProvider = OpenMeteo()

    /// Weather forecasts are off until people turn them on.
    static let optInKey = "weatherForecasts"
    static var allowed: Bool { UserDefaults.standard.bool(forKey: optInKey) }

    private static var cache: [String: (fetched: Date, days: [DayForecast])] = [:]
    private static let lock = NSLock()

    static func key(_ lat: Double, _ lon: Double) -> String { String(format: "%.2f,%.2f", lat, lon) }

    /// Cached for an hour, so the Shot List and the PDF share one fetch.
    static func days(latitude: Double, longitude: Double) async throws -> [DayForecast] {
        let k = key(latitude, longitude)
        if let hit = cached(k) { return hit }
        let lat = (latitude * 100).rounded() / 100, lon = (longitude * 100).rounded() / 100
        let days = try await provider.days(latitude: lat, longitude: lon)
        lock.lock(); cache[k] = (Date(), days); lock.unlock()
        return days
    }

    /// With forecasts on, fetch each scene's weather first so the Detailed PDF can print it.
    /// Quietly skipped offline.
    static func prefetch(project: Project, scene: ScoutScene?) async {
        guard allowed else { return }
        for sc in scene.map({ [$0] }) ?? project.scenes {
            guard let p = Exporter.place(of: sc) else { continue }
            _ = try? await days(latitude: p.latitude, longitude: p.longitude)
        }
    }

    /// Whatever was fetched in the last hour, for the PDF (which never fetches on its own).
    static func cached(latitude: Double, longitude: Double) -> [DayForecast]? { cached(key(latitude, longitude)) }

    private static func cached(_ k: String) -> [DayForecast]? {
        lock.lock(); defer { lock.unlock() }
        guard let hit = cache[k], Date().timeIntervalSince(hit.fetched) < 3600 else { return nil }
        return hit.days
    }
}

struct OpenMeteo: ForecastProvider {
    let credit = "Weather data by Open-Meteo.com (CC BY 4.0)"

    private struct Response: Decodable {
        struct Daily: Decodable {
            var time: [String]
            var weather_code: [Int?]
            var temperature_2m_max: [Double?]
            var temperature_2m_min: [Double?]
            var precipitation_probability_max: [Int?]
            var sunshine_duration: [Double?]
            var wind_speed_10m_max: [Double?]
        }
        struct Hourly: Decodable {
            var time: [String]
            var cloud_cover: [Int?]
        }
        var daily: Daily
        var hourly: Hourly
    }

    func days(latitude: Double, longitude: Double) async throws -> [DayForecast] {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(format: "%.2f", latitude)),
            .init(name: "longitude", value: String(format: "%.2f", longitude)),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunshine_duration,wind_speed_10m_max"),
            .init(name: "hourly", value: "cloud_cover"),
            .init(name: "timezone", value: TimeZone.current.identifier),
            .init(name: "forecast_days", value: "14"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        let d = r.daily
        return d.time.indices.compactMap { i in
            guard let date = f.date(from: d.time[i]) else { return nil }
            let hours = (0..<24).map { h in
                let j = i * 24 + h
                return r.hourly.cloud_cover.indices.contains(j) ? (r.hourly.cloud_cover[j] ?? 0) : 0
            }
            return DayForecast(
                date: date,
                code: d.weather_code[i] ?? -1,
                tempMax: d.temperature_2m_max[i] ?? 0,
                tempMin: d.temperature_2m_min[i] ?? 0,
                rain: d.precipitation_probability_max[i] ?? 0,
                sunHours: (d.sunshine_duration[i] ?? 0) / 3600,
                wind: d.wind_speed_10m_max[i] ?? 0,
                hourlyCloud: hours
            )
        }
    }
}
