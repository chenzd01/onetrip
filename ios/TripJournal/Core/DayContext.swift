import Foundation

struct DayContext {
    enum Phase { case before, traveling, after }
    let phase: Phase
    let day: TripDay?
    let upcoming: [Stop]
    let flexible: [Stop]
    let tonight: [Stay]
    let checkingOut: [Stay]
    let ticketPlaces: [String]

    init(plan: TripPlan, places: [Place], now: Date) {
        let key = TripClock.dayKey(now)
        day = plan.days.first { $0.date == key }
        let timed: [(stop: Stop, start: Date)] = plan.days.flatMap { day in
            day.items.compactMap { item in
                guard !item.time.isEmpty, let start = TripClock.date(day.date + "T" + item.time) else { return nil }
                let minutes = item.duration(fallbackHours: places.first { $0.id == item.place }?.hours ?? 0)
                let end = start.addingTimeInterval(Double(max(0, minutes)) * 60)
                guard (start <= now && end > now) || (day.date == key && start >= now) else { return nil }
                return (item, start)
            }
        }
        upcoming = timed.enumerated().sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }.map { $0.element.stop }
        phase = key < (plan.days.first?.date ?? key) ? .before : key > (plan.days.last?.date ?? key) && upcoming.isEmpty ? .after : .traveling
        flexible = (day?.items ?? []).filter { $0.time.isEmpty }
        tonight = (plan.stays ?? []).filter { $0.checkIn <= key && $0.checkOut > key }
        checkingOut = (plan.stays ?? []).filter { $0.checkOut == key }
        let scheduled = Set((day?.items ?? []).map(\.place))
        ticketPlaces = (plan.tickets ?? [:]).keys.filter { place in
            (plan.tickets?[place] ?? []).contains { ticket in
                ticket.status != "cancelled" && (ticket.date == key || (ticket.date.isEmpty && scheduled.contains(place)))
            }
        }.sorted()
    }
}
