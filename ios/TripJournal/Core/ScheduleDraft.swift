import Foundation

struct ScheduleDraft: Equatable {
    var isTimed: Bool
    var start: Date
    var end: Date
    var endsNextDay: Bool

    init(item: Stop? = nil, suggestedHours: Double = 1, isTimed: Bool = true) {
        self.isTimed = item.map { !$0.time.isEmpty } ?? isTimed
        let anchor = TripClock.date("2001-01-01")!
        start = item.flatMap { TripClock.date("2001-01-01T" + $0.time) } ?? anchor.addingTimeInterval(11 * 3600)
        let minutes = min(1440, max(1, item?.duration(fallbackHours: suggestedHours) ?? Int((suggestedHours * 60).rounded())))
        let finish = start.addingTimeInterval(Double(minutes) * 60)
        endsNextDay = TripClock.dayKey(finish) != TripClock.dayKey(start)
        end = anchor.addingTimeInterval(Double(Self.minute(finish)) * 60)
    }
    private static func minute(_ date: Date) -> Int {
        TripClock.calendar.component(.hour, from: date) * 60 + TripClock.calendar.component(.minute, from: date)
    }
    var durationMinutes: Int { Self.minute(end) - Self.minute(start) + (endsNextDay ? 1440 : 0) }
    var isValid: Bool { !isTimed || (1...1440).contains(durationMinutes) }
    var time: String {
        guard isTimed else { return "" }
        let minutes = Self.minute(start)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
    var validationMessage: String? {
        guard isTimed && !isValid else { return nil }
        return durationMinutes <= 0 ? "结束时间须晚于开始时间；跨午夜请选择「次日结束」。" : "单个安排最长为 24 小时，请调整结束时间。"
    }
    func apply(to item: inout Stop) {
        item.time = time
        item.durationMinutes = isTimed ? durationMinutes : nil
    }
}
