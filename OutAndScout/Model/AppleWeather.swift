import CoreLocation
import Foundation
import WeatherKit

/// Apple WeatherKit (18 Nov 2026, for the App Store build): Open-Meteo's free tier is
/// non-commercial, and Pro makes the app commercial. Ten days ahead (WeatherKit's limit).
/// Only the spot, rounded to about 1 km, is sent, to Apple. No account or user id.
struct AppleWeather: ForecastProvider {
    let credit = "Apple Weather"
    /// Apple asks for this link wherever the forecast shows.
    static let legalURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!

    func days(latitude: Double, longitude: Double) async throws -> [DayForecast] {
        let place = CLLocation(latitude: latitude, longitude: longitude)
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 10, to: start) ?? start.addingTimeInterval(864_000)
        let (daily, hourly) = try await WeatherService.shared.weather(
            for: place,
            including: .daily(startDate: start, endDate: end), .hourly(startDate: start, endDate: end)
        )

        var clouds: [Date: [Int]] = [:]
        var wind: [Date: Double] = [:]
        for hour in hourly {
            let day = cal.startOfDay(for: hour.date)
            let h = cal.component(.hour, from: hour.date)
            var row = clouds[day] ?? Array(repeating: 0, count: 24)
            if row.indices.contains(h) { row[h] = Int((hour.cloudCover * 100).rounded()) }
            clouds[day] = row
            wind[day] = max(wind[day] ?? 0, hour.wind.speed.converted(to: .kilometersPerHour).value)
        }

        return daily.map { day in
            let date = cal.startOfDay(for: day.date)
            let cloud = clouds[date] ?? Array(repeating: 0, count: 24)
            // Sunshine: daylight hours, each counted by how clear it is.
            var sun = 0.0
            if let rise = day.sun.sunrise, let set = day.sun.sunset {
                for h in 0..<24 {
                    guard let mid = cal.date(byAdding: .minute, value: h * 60 + 30, to: date) else { continue }
                    if mid > rise && mid < set { sun += 1 - Double(cloud[h]) / 100 }
                }
            }
            return DayForecast(
                date: date,
                code: Self.code(day.condition),
                tempMax: day.highTemperature.converted(to: .celsius).value,
                tempMin: day.lowTemperature.converted(to: .celsius).value,
                rain: Int((day.precipitationChance * 100).rounded()),
                sunHours: sun,
                wind: wind[date] ?? day.wind.speed.converted(to: .kilometersPerHour).value,
                hourlyCloud: cloud
            )
        }
    }

    /// Apple's conditions as the WMO codes DayForecast.summary already reads.
    static func code(_ c: WeatherCondition) -> Int {
        switch c {
        case .clear, .hot: return 0
        case .mostlyClear: return 1
        case .partlyCloudy: return 2
        case .mostlyCloudy, .cloudy: return 3
        case .foggy, .haze, .smoky, .blowingDust: return 45
        case .drizzle, .freezingDrizzle: return 51
        case .rain, .heavyRain, .freezingRain, .sleet, .hail: return 61
        case .snow, .heavySnow, .flurries, .blowingSnow, .blizzard, .frigid, .wintryMix: return 71
        case .sunShowers: return 80
        case .sunFlurries: return 85
        case .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms, .tropicalStorm, .hurricane: return 95
        default: return -1
        }
    }
}
