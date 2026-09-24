import Foundation

// Destination-level settings from content/trip.json. Everything that used to be
// hard-coded for one trip (dates, timezone, currency, map region, names) lives here.
struct TripConfig: Codable, Sendable {
    struct Destination: Codable, Sendable {
        var name: String
        var nameEn: String
        var countryCode: String
        // Appended to map searches and English addresses, e.g. "Kyoto".
        var addressSuffix: String
        // Optional regex for a postal code inside English addresses, e.g. "\\d{3}-\\d{4}".
        var postcodePattern: String?
    }
    struct Currency: Codable, Sendable {
        var local: String
        var home: String
        var localSymbol: String
        var homeSymbol: String
        var homePerLocal: Double
        var rateDate: String
        var rateSource: String
    }
    struct Bounds: Codable, Sendable {
        var minLat: Double
        var maxLat: Double
        var minLon: Double
        var maxLon: Double
        func contains(latitude: Double, longitude: Double) -> Bool {
            (minLat...maxLat).contains(latitude) && (minLon...maxLon).contains(longitude)
        }
    }
    struct MapRegion: Codable, Sendable {
        var center: [Double]
        var span: [Double]
        var bounds: Bounds
    }
    struct Speech: Codable, Sendable {
        // BCP-47 voice language for the phrasebook, e.g. "en-US" or "ja-JP".
        var language: String
        var label: String
    }
    var id: String
    var appName: String
    var tagline: String
    var destination: Destination
    var timezone: String
    // First and last itinerary day (yyyy-MM-dd). The day list is derived from them.
    var startDate: String
    var endDate: String
    // Day the travellers leave home; may be before startDate for overnight flights.
    var departureDate: String
    var homeCity: String
    var partySize: Int
    var currency: Currency
    var map: MapRegion
    var speech: Speech
    var attributions: [SourceLink]

    var dayKeys: [String] {
        guard let start = TripClock.date(startDate), let end = TripClock.date(endDate), start <= end else { return [startDate] }
        var keys: [String] = [], day = start
        while day <= end, keys.count < 60 {
            keys.append(TripClock.dayKey(day))
            guard let next = TripClock.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return keys
    }
    var dayCount: Int { dayKeys.count }
    var nightCount: Int { max(dayCount - 1, 0) }
    // Stays may start on the departure day (overnight flights) and end on the last day.
    var stayRange: (first: String, last: String) { (min(departureDate, startDate), endDate) }
    var dateRangeLabel: String { Self.shortDate(startDate) + " — " + Self.shortDate(endDate) }
    static func shortDate(_ key: String) -> String {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        return parts.count == 3 ? "\(parts[1]).\(parts[2])" : key
    }

    static let current: TripConfig = load() ?? .fallback

    private static func load() -> TripConfig? {
        // The app bundles it under Content/; the widget extension bundles a top-level copy.
        let url = Bundle.main.url(forResource: "trip", withExtension: "json", subdirectory: "Content")
            ?? Bundle.main.url(forResource: "trip", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TripConfig.self, from: data)
    }

    // Used only when trip.json is missing (e.g. a widget preview); never ships as content.
    static let fallback = TripConfig(
        id: "trip", appName: "旅行手帐", tagline: "", destination: .init(name: "目的地", nameEn: "Destination", countryCode: "", addressSuffix: "", postcodePattern: nil),
        timezone: TimeZone.current.identifier, startDate: "2030-01-01", endDate: "2030-01-01", departureDate: "2030-01-01", homeCity: "",
        partySize: 2, currency: .init(local: "USD", home: "CNY", localSymbol: "$", homeSymbol: "¥", homePerLocal: 1, rateDate: "", rateSource: ""),
        map: .init(center: [0, 0], span: [1, 1], bounds: .init(minLat: -90, maxLat: 90, minLon: -180, maxLon: 180)),
        speech: .init(language: "en-US", label: "英语"), attributions: [])
}

// Shared with the widget extension, which compiles only Shared/.
struct SourceLink: Codable, Hashable, Sendable {
    var label: String
    var url: String
}

// Build-time identifiers injected through Info.plist from the xcconfig files.
enum AppIdentity {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "tripjournal" }
    // Widget extensions have a ".widgets" suffix; keychain and logs use the app's ID.
    static var appBundleID: String { bundleID.hasSuffix(".widgets") ? String(bundleID.dropLast(".widgets".count)) : bundleID }
    static var appGroup: String { (Bundle.main.object(forInfoDictionaryKey: "TripAppGroup") as? String) ?? "group." + appBundleID }
    static var serverURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TripServerURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw.hasSuffix("/") ? raw : raw + "/"),
              url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost" else { return nil }
        return url
    }
}
