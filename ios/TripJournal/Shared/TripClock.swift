import Foundation
import ActivityKit

// All itinerary timestamps are destination local time, independent of device timezone.
enum TripClock {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: TripConfig.current.timezone) ?? .current
        return c
    }
    static func date(_ string: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = string.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        f.isLenient = false
        return f.date(from: string)
    }
    /// The current time. DEBUG builds accept the launch argument `-TripNow yyyy-MM-ddTHH:mm` (destination local
    /// time) to freeze the clock on any trip day, for screenshots and manual checks. Release builds ignore it.
    static var now: Date {
        #if DEBUG
        if let fixedNow { return fixedNow }
        #endif
        return .now
    }
    #if DEBUG
    private static let fixedNow = UserDefaults.standard.string(forKey: "TripNow").flatMap { date($0) }
    #endif
    static func dayKey(_ date: Date = TripClock.now) -> String {
        let f = DateFormatter(); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    static func daysUntilDeparture(_ now: Date = TripClock.now) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date(TripConfig.current.departureDate) ?? now).day ?? 0
    }
}
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var time: String
        var day: String
        var nextDate: Date?
    }
    var tripName: String
}
struct WidgetSnapshot: Codable {
    var title: String
    var subtitle: String
    var time: String
    var date: Date
    static var group: String { AppIdentity.appGroup }
    static var tripSubtitle: String { TripConfig.current.dateRangeLabel + " · " + TripConfig.current.destination.name }
    static var initial: Self { .init(title: TripConfig.current.appName, subtitle: tripSubtitle, time: "", date: .now) }
}

// Contains only public destination names and dates, never ticket codes or notes.
struct TravelSchedule: Codable, Sendable {
    struct Event: Codable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var time: String
    }
    var events: [Event]
    var dayKeys: [String]
    func snapshot(at now: Date) -> WidgetSnapshot {
        let key = TripClock.dayKey(now)
        let trip = TripConfig.current
        if key < (dayKeys.first ?? trip.startDate) {
            return .init(title: TripClock.daysUntilDeparture(now) > 0 ? "\(TripClock.daysUntilDeparture(now)) 天后，一起出发" : "今天，一起出发", subtitle: WidgetSnapshot.tripSubtitle, time: "", date: now)
        }
        if let event = events.first(where: { (TripClock.dayKey($0.start) == key || $0.start <= now) && $0.end > now }) {
            return .init(title: event.title, subtitle: trip.destination.name + " · 按计划接下来", time: event.time, date: now)
        }
        if key > (dayKeys.last ?? trip.endDate) { return .init(title: "把这些日子，好好收藏", subtitle: "打开这 \(max(dayKeys.count, 1)) 天的旅行手帐", time: "", date: now) }
        return .init(title: "留一点时间，随心走走", subtitle: "今天的完整安排在 App 里", time: "", date: now)
    }
    func transitions(after now: Date) -> [Date] {
        let midnights = dayKeys.compactMap { TripClock.date($0) }
        let end = dayKeys.last.flatMap { TripClock.date($0) }.flatMap { TripClock.calendar.date(byAdding: .day, value: 1, to: $0) }
        return Array(Set(events.flatMap { [$0.start,$0.end] } + midnights + [end].compactMap { $0 })).filter { $0 > now }.sorted()
    }
}
