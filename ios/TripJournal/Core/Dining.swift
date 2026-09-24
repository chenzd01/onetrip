import Foundation

struct MealPlan: Codable, Equatable, Sendable {
    var kind = "lunch"
    var reservation = DiningReservation()
    static let kinds = ["breakfast", "lunch", "dinner", "snack"]
    static func label(_ kind: String) -> String {
        ["breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐", "snack": "加餐"][kind] ?? "用餐"
    }
}

struct DiningReservation: Codable, Equatable, Sendable {
    var status = "planned"
    var date = ""
    var time = ""
    var partySize = TripConfig.current.partySize
    var reference = ""
    var notes = ""
    static let statuses = ["notRequired", "planned", "booked", "cancelled"]
    var label: String {
        ["notRequired": "无需预约", "planned": "待预订", "booked": "已预订", "cancelled": "已取消"][status] ?? "待核对"
    }
    func differs(from item: Stop, day: String) -> Bool {
        status == "booked" && !date.isEmpty && !time.isEmpty && (date != day || time != item.time)
    }
}

struct DiningSource: Codable, Hashable, Sendable {
    var title: String
    var url: String
    var checkedAt: String
}

struct DiningMenu: Codable, Hashable, Sendable {
    var name: String
    var meal: String
    var price: Double?
    var priceMax: Double?
    var basis: String
    var tax: String
    var includes: String
    var sourceURL: String
    var checkedAt: String
    var serviceChargePercent: Double?
    var taxPercent: Double?
    var totalPerPerson: Double? {
        guard basis == "perPerson" || basis == "estimate", let price else { return nil }
        if tax == "nett" { return price }
        guard let serviceChargePercent, let taxPercent else { return nil }
        return price * (1 + serviceChargePercent / 100) * (1 + taxPercent / 100)
    }
}

struct DiningVenue: Codable, Identifiable, Sendable {
    struct Award: Codable, Sendable {
        var kind: String
        var stars: Int?
        var year: Int?
        var sourceURL: String?
        var label: String {
            let title: String
            switch kind {
            case "stars": title = "米其林" + [1: "一星", 2: "二星", 3: "三星"][stars ?? 0, default: "星级待核"]
            case "bibGourmand": title = "必比登推介"
            case "selected": title = "米其林指南入选"
            case "unverified": title = "荣誉待核实"
            default: return ""
            }
            return title + (year.map { " · \($0)" } ?? "")
        }
    }
    struct Coordinates: Codable, Sendable { var latitude: Double; var longitude: Double }
    struct Observation: Codable, Identifiable, Sendable {
        var date: String
        var meal: String
        var partySize: Int
        var status: String
        var detail: String
        var checkedAt: String
        var sourceURL: String
        var id: String { date + meal + checkedAt + sourceURL }
    }
    struct Booking: Codable, Sendable {
        var url: String
        var policy: String
        var releaseRule: String?
        var cancellation: String?
        var availability: String
        var checkedAt: String
        var observations: [Observation]?
    }
    var id: String
    var name: String
    var en: String
    var zone: String
    var type: String
    var cuisines: [String]
    var award: Award
    var description: String
    var address: String
    var coordinates: Coordinates?
    var menus: [DiningMenu]
    var booking: Booking
    var hours: String
    var durationMinutes: Int?
    var closedWeekdays: [Int]?
    var closedDates: [String]?
    var tips: [String]
    var sources: [DiningSource]
    var depth: String
    var isRestaurant: Bool { type == "restaurant" }
    func referenceMenu(for meal: String? = nil) -> DiningMenu? {
        let priced = menus.filter { $0.price != nil }
        guard let meal else { return priced.first }
        return priced.first { $0.meal == meal } ?? priced.first { ["any", "both", "allDay"].contains($0.meal) }
    }
}

struct DiningGuide: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String
    var body: [String]
    var restaurantIDs: [String]
    var sources: [DiningSource]
}

struct DiningRecommendation: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var day: Int
    var meal: String
    var restaurantIDs: [String]
    var reason: String
}

struct DiningCatalog: Codable, Sendable {
    struct Directory: Codable, Sendable {
        var edition: Int
        var status: String
        var sourceURL: String
        var notes: String
    }
    var version: Int
    var checkedAt: String
    var currency: String
    var directory: Directory
    var restaurants: [DiningVenue]
    var recommendations: [DiningRecommendation]
    var guides: [DiningGuide]?
    func venue(_ id: String) -> DiningVenue? { restaurants.first { $0.id == id } }
}

enum DiningSchedule {
    static func apply(_ item: Stop, to plan: inout TripPlan, day: Int) {
        if let index = plan.days[day].items.firstIndex(where: { $0.uid == item.uid }) {
            plan.days[day].items[index] = item
        } else {
            for index in plan.days.indices { plan.days[index].items.removeAll { $0.uid == item.uid } }
            plan.days[day].items.append(item)
        }
    }
    static func isClosed(_ venue: DiningVenue, on date: String) -> Bool {
        if venue.closedDates?.contains(date) == true { return true }
        guard let value = TripClock.date(date), let weekdays = venue.closedWeekdays else { return false }
        return weekdays.contains((TripClock.calendar.component(.weekday, from: value) + 5) % 7 + 1)
    }
    static func warnings(item: Stop, day: TripDay, places: [Place], venue: DiningVenue?) -> [String] {
        var warnings: [String] = []
        if let venue, isClosed(venue, on: day.date) {
            warnings.append("这一天是餐厅公布的休息日，请核对最新营业安排。")
        }
        if let start = TripClock.date(day.date + "T" + item.time) {
            let ownPlace = places.first { $0.id == item.place }
            let end = start.addingTimeInterval(Double(item.duration(fallbackHours: ownPlace?.hours ?? 1)) * 60)
            for other in day.items where other.uid != item.uid {
                guard let otherStart = TripClock.date(day.date + "T" + other.time) else { continue }
                let place = places.first { $0.id == other.place }
                let otherEnd = otherStart.addingTimeInterval(Double(other.duration(fallbackHours: place?.hours ?? 1)) * 60)
                if start < otherEnd && end > otherStart { warnings.append("与「\(place?.name ?? "其他安排")」时间重叠，请预留用餐和交通时间。") }
            }
        }
        if item.meal?.reservation.differs(from: item, day: day.date) == true {
            warnings.append("行程时间与已记录的预约不同。修改行程不会更改餐厅订单，请联系餐厅确认。")
        }
        return warnings
    }
}
