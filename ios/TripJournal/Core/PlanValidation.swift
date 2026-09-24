import Foundation

enum PlanValidation {
    // Per-line trip total; must match the backend's plan validation.
    // High enough for low-value currencies (JPY, KRW…): a week of hotels is often several hundred thousand.
    static let maximumBudget: Double = 10_000_000
    static func validate(_ p: TripPlan, catalog: ContentCatalog) throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw TripError.message(message) } }
        func text(_ value: String, _ maximum: Int = 5000) -> Bool { value.unicodeScalars.count <= maximum }
        func time(_ value: String) -> Bool { value.isEmpty || value.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil }
        func link(_ value: String) -> Bool { value.isEmpty || (URL(string: value).map { ["http", "https"].contains($0.scheme ?? "") && $0.host != nil } ?? false) }
        func recordID(_ value: String) -> Bool { value.range(of: "^[a-z0-9-]{1,80}$", options: .regularExpression) != nil }
        try require(p.version == 1 && p.id == catalog.defaults.id, "不是本次旅行的有效备份")
        try require(p.days.map(\.date) == catalog.catalog.days.map(\.date), "请保留本次旅行的全部 \(catalog.catalog.days.count) 个日期")
        let places = catalog.catalog.places + p.custom
        try require(Set(places.map(\.id)).count == places.count && p.custom.count <= 200, "自定义地点编号重复或数量过多")
        for place in p.custom {
            try require(text(place.id,120) && [place.name,place.en,place.zone,place.kind,place.desc,place.tip,place.travel,place.rain,place.food,place.link].allSatisfy { text($0) }, "自定义地点资料过长")
            try require(place.hours.isFinite && (0...24).contains(place.hours) && place.budget.isFinite && (0...maximumBudget).contains(place.budget), "请检查自定义地点时长与预算")
            try require(link(place.link), "地点链接须为 http 或 https 网址")
        }
        try require(p.checks.count <= 100 && p.checks.keys.allSatisfy { text($0,120) }, "清单状态无效")
        let favorites = p.hotelFavorites ?? []
        try require(favorites.count <= 100 && Set(favorites).count == favorites.count && favorites.allSatisfy(recordID), "酒店收藏无效")
        let ids = Set(places.map(\.id)), items = p.days.flatMap(\.items)
        try require(Set(items.map(\.uid)).count == items.count, "同一个安排被移动到了不同日期，请选择要保留的版本")
        try require(p.days.allSatisfy { $0.items.count <= 100 }, "单日最多 100 项安排")
        try require(p.days.allSatisfy { [ $0.title, $0.area, $0.note ].allSatisfy { text($0) } }, "每日说明过长")
        for item in items {
            try require(ids.contains(item.place), "有安排引用了不存在的地点")
            try require(item.time.isEmpty || item.time.range(of: #"^([01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil, "时间格式应为 HH:mm")
            try require(text(item.note) && text(item.uid,120), "备注或行程编号过长")
            if let duration = item.durationMinutes {
                try require(!item.time.isEmpty && (1...1440).contains(duration), "安排时长须在 1 分钟到 24 小时之间，并设置开始时间")
            }
            if let meal = item.meal {
                let r = meal.reservation
                try require(places.contains { $0.id == item.place && $0.isDining }, "用餐须关联餐饮地点")
                try require(MealPlan.kinds.contains(meal.kind) && DiningReservation.statuses.contains(r.status), "请检查餐别和预约状态")
                try require((1...20).contains(r.partySize), "用餐人数须在 1 到 20 人之间")
                try require(r.date.isEmpty || p.days.contains { $0.date == r.date }, "预约日期须在本次旅行日期内")
                try require(time(r.time) && text(r.reference, 500) && text(r.notes, 3000), "请检查预约时间、确认号和备注")
                try require(r.status != "booked" || (!r.date.isEmpty && !r.time.isEmpty), "已预订餐食请填写餐厅确认的日期和时间")
            }
        }
        let amounts: [Double] = [p.budget.flightOut, p.budget.flightReturn, p.budget.hotel, p.budget.food, p.budget.transport, p.budget.other]
        for value in amounts {
            try require(value.isFinite && (0...maximumBudget).contains(value), "预算须在 0 到 \(Int(maximumBudget)) 之间")
        }
        let range = TripConfig.current.stayRange
        let stays = (p.stays ?? []).sorted { $0.checkIn < $1.checkIn }
        try require(stays.count <= 20 && Set(stays.map(\.id)).count == stays.count, "酒店数量或编号无效")
        for (i, stay) in stays.enumerated() {
            try require(!stay.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "请填写酒店名称")
            try require(recordID(stay.id) && [stay.name,stay.nameEnglish ?? "",stay.address,stay.phone,stay.checkIn,stay.checkOut,stay.checkInTime,stay.checkOutTime].allSatisfy { text($0,300) } && text(stay.notes,3000), "酒店资料过长或编号无效")
            try require(time(stay.checkInTime) && time(stay.checkOutTime), "入住退房时间应为 HH:mm")
            try require([stay.checkIn, stay.checkOut].allSatisfy { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil } && stay.checkIn >= range.first && stay.checkIn < range.last && stay.checkOut > range.first && stay.checkOut <= range.last, "酒店日期须在本次旅行范围内")
            try require(stay.checkIn < stay.checkOut && TripClock.date(stay.checkIn) != nil && TripClock.date(stay.checkOut) != nil, "请检查入住和退房日期")
            if i > 0 { try require(stays[i-1].checkOut <= stay.checkIn, "酒店住宿日期有重叠") }
        }
        var ticketIDs = Set<String>()
        try require((p.tickets ?? [:]).count <= 236, "门票地点数量过多")
        for (place, tickets) in p.tickets ?? [:] {
            try require(ids.contains(place) && tickets.count <= 12, "门票地点无效或数量超过 12 条")
            for t in tickets {
                try require(ticketIDs.insert(t.id).inserted && !t.title.trimmingCharacters(in: .whitespaces).isEmpty, "门票名称或编号无效")
                try require(recordID(t.id) && [t.title,t.date,t.time,t.provider,t.reference,t.url,t.deadline].allSatisfy { text($0,500) } && text(t.notes,3000), "门票资料过长或编号无效")
                try require(time(t.time) && link(t.url), "请检查门票时间和预订网址")
                try require(t.deadline.isEmpty || (t.deadline.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil && TripClock.date(t.deadline) != nil), "退改截止时间格式应为 YYYY-MM-DDTHH:mm")
                try require(["planned","booked","used","cancelled"].contains(t.status) && (1...20).contains(t.quantity), "请检查门票状态和人数")
                try require(t.date.isEmpty || p.days.contains { $0.date == t.date }, "门票日期须在旅行日期内")
                try require(t.files.count <= 8 && Set(t.files.map(\.id)).count == t.files.count, "每条门票最多 8 个不同附件")
                try require(t.files.allSatisfy { (1...10*1024*1024).contains($0.size) && ["image/jpeg","image/png","image/webp","application/pdf"].contains($0.type) && $0.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }, "门票附件无效")
                try require(t.files.allSatisfy { text($0.name,200) }, "附件文件名过长")
            }
        }
    }
}
enum TripError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}
