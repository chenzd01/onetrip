import Foundation
import Observation
import UserNotifications

struct TravelReminder: Identifiable, Sendable {
    var id: String
    var label: String
    var date: Date
    var safeBody: String
}
enum ReminderPlanner {
    static func candidates(plan: TripPlan, content: ContentCatalog) -> [TravelReminder] {
        var result = content.flights.compactMap { flight -> TravelReminder? in
            guard let date = TripClock.date(flight.departure) else { return nil }
            return .init(id: "flight-" + flight.id, label: flight.number + " · 航班出发", date: date, safeBody: "航班即将出发，打开旅行手帐核对安排。")
        }
        for day in plan.days {
            for item in day.items where !item.time.isEmpty {
                guard let date = TripClock.date(day.date + "T" + item.time) else { continue }
                let name = (content.catalog.places + plan.custom).first { $0.id == item.place }?.name ?? "行程安排"
                result.append(.init(id: "stop-" + item.uid, label: name + " · 计划出发", date: date, safeBody: "接下来的安排快到了，打开旅行手帐查看。"))
            }
        }
        for tickets in (plan.tickets ?? [:]).values {
            for ticket in tickets where !["cancelled","used"].contains(ticket.status) {
                if !ticket.date.isEmpty, !ticket.time.isEmpty, let date = TripClock.date(ticket.date + "T" + ticket.time) {
                    result.append(.init(id:"ticket-" + ticket.id, label:ticket.title + " · 入场", date:date, safeBody:"票券使用时间快到了，打开旅行手帐查看。"))
                }
                if let date = TripClock.date(ticket.deadline), !ticket.deadline.isEmpty {
                    result.append(.init(id:"deadline-" + ticket.id, label:ticket.title + " · 退改截止", date:date, safeBody:"有一张票券即将到退改截止时间，请打开旅行手帐核对。"))
                }
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
    static func scheduled(_ candidates: [TravelReminder], preferences: [String:Int], now: Date) -> [(TravelReminder,Date)] {
        candidates.compactMap { item in
            guard let minutes = preferences[item.id] else { return nil }
            let date = item.date.addingTimeInterval(-Double(minutes) * 60)
            return date > now ? (item,date) : nil
        }.sorted { $0.1 < $1.1 }
    }
}
@MainActor @Observable final class ReminderController {
    private(set) var preferences: [String:Int]
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var status = "提醒默认关闭，仅在这部手机生效"
    private let center = UNUserNotificationCenter.current()
    private var queue: Task<Void,Never>?
    private var generation = 0
    init() {
        preferences = UserDefaults.standard.data(forKey:"travel-reminders").flatMap { try? JSONDecoder().decode([String:Int].self,from:$0) } ?? [:]
    }
    func set(_ id: String, minutes: Int?, candidates: [TravelReminder]) async throws {
        if minutes != nil {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined { _ = try await center.requestAuthorization(options: [.alert,.sound]) }
            authorization = await center.notificationSettings().authorizationStatus
            guard authorization == .authorized || authorization == .provisional else { throw TripError.message("通知权限未开启。请前往系统设置允许通知，再开启这一项。") }
        }
        var next = preferences; next[id] = minutes
        let data = try JSONEncoder().encode(next)
        UserDefaults.standard.set(data,forKey:"travel-reminders"); preferences = next
        refresh(candidates)
    }
    func refresh(_ candidates: [TravelReminder]) {
        generation += 1
        let expected = generation, previous = queue
        queue = Task {
            await previous?.value
            guard expected == generation else { return }
            authorization = await center.notificationSettings().authorizationStatus
            let pending = await center.pendingNotificationRequests()
            guard expected == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers:pending.map(\.identifier).filter { $0.hasPrefix("travel-") })
            guard authorization == .authorized || authorization == .provisional else { status = preferences.isEmpty ? "提醒默认关闭，仅在这部手机生效" : "系统通知未开启，已取消本机待发提醒"; return }
            let scheduled = ReminderPlanner.scheduled(candidates, preferences: preferences, now: .now)
            var count = 0
            do {
                for (item,date) in scheduled.prefix(60) {
                    guard expected == generation else { return }
                    let content = UNMutableNotificationContent(); content.title = TripConfig.current.appName; content.body = item.safeBody; content.sound = .default
                    var components = TripClock.calendar.dateComponents([.year,.month,.day,.hour,.minute],from:date)
                    components.timeZone = TripClock.calendar.timeZone
                    try await center.add(UNNotificationRequest(identifier:"travel-" + item.id,content:content,trigger:UNCalendarNotificationTrigger(dateMatching:components,repeats:false)))
                    count += 1
                }
                status = scheduled.count > 60 ? "已安排最近 60 项；打开 App 后续排剩余提醒" : "已安排 \(count) 项本机提醒"
            } catch { status = "部分提醒未安排成功，请重试：" + error.localizedDescription }
        }
    }
}
