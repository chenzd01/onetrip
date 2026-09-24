import XCTest
@testable import TripJournal

final class ScheduleTests: XCTestCase {
    func testChronologicalOrderKeepsTiesAndFlexibleItemsStable() throws {
        var day = try ContentCatalog.load().defaults.days[0]
        day.items = [("five", "05:00"), ("flex-a", ""), ("seven", "07:00"), ("flex-b", ""), ("six", "06:00"), ("six-b", "06:00")].map {
            Stop(uid: $0.0, place: TestTrip.place, time: $0.1, note: "")
        }
        XCTAssertEqual(day.chronologicalItems.map(\.uid), ["five", "six", "six-b", "seven", "flex-a", "flex-b"])
        day.items[4].time = "04:30"
        XCTAssertEqual(day.chronologicalItems.first?.uid, "six")
    }

    func testOvernightStaysVisibleUntilActualEndIncludingFinalDay() throws {
        let content = try ContentCatalog.load()
        for dayIndex in [0, content.defaults.days.count - 1] {
            var plan = content.defaults
            for index in plan.days.indices { plan.days[index].items = [] }
            let stop = Stop(uid: "overnight", place: TestTrip.place, time: "23:00", note: "", durationMinutes: 120)
            plan.days[dayIndex].items = [stop]
            let start = TripClock.date(plan.days[dayIndex].date + "T23:00")!
            let end = start.addingTimeInterval(7200)
            let during = DayContext(plan: plan, places: content.catalog.places, now: end.addingTimeInterval(-60))
            XCTAssertEqual(during.upcoming.map(\.uid), [stop.uid])
            XCTAssertEqual(during.phase, .traveling)
            XCTAssertTrue(DayContext(plan: plan, places: content.catalog.places, now: end).upcoming.isEmpty)
            let schedule = TravelSchedule(events: [.init(title: "overnight", start: start, end: end, time: stop.time)], dayKeys: plan.days.map(\.date))
            XCTAssertEqual(schedule.snapshot(at: end.addingTimeInterval(-60)).title, "overnight")
            XCTAssertNotEqual(schedule.snapshot(at: end).title, "overnight")
            XCTAssertTrue(schedule.transitions(after: start).contains(end))
        }
    }

    func testTimeRangeAndMinuteFormatting() {
        var draft = ScheduleDraft()
        draft.start = TripClock.date("2001-01-01T06:00")!
        draft.end = TripClock.date("2001-01-01T08:00")!
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.durationMinutes, 120)
        var stop = Stop(uid: "test", place: TestTrip.place, time: "", note: "")
        draft.apply(to: &stop)
        XCTAssertEqual(stop.scheduleLabel(fallbackHours: 0.75), "06:00 + 2 小时")
        XCTAssertEqual(Stop.durationLabel(45), "45 分钟")
        XCTAssertEqual(Stop.durationLabel(90), "1 小时 30 分钟")
        draft.end = TripClock.date("2001-01-01T08:15")!
        XCTAssertEqual(draft.durationMinutes, 135)
    }

    func testMidnightRequiresExplicitNextDayAndRejectsInvalidRanges() {
        var draft = ScheduleDraft()
        draft.start = TripClock.date("2001-01-01T23:30")!
        draft.end = TripClock.date("2001-01-01T01:00")!
        XCTAssertFalse(draft.isValid)
        XCTAssertNotNil(draft.validationMessage)
        draft.endsNextDay = true
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(draft.durationMinutes, 90)
        draft.end = draft.start
        XCTAssertEqual(draft.durationMinutes, 1440)
        XCTAssertTrue(draft.isValid)
        draft.endsNextDay = false
        XCTAssertFalse(draft.isValid)
        draft.endsNextDay = true
        draft.end = TripClock.date("2001-01-01T23:31")!
        XCTAssertFalse(draft.isValid)
        draft.isTimed = false
        XCTAssertTrue(draft.isValid)
    }

    func testLegacyRoundTripAndPerStopDurations() throws {
        let old = Data(#"{"uid":"old","place":"harbor-light","time":"06:00","note":"keep"}"#.utf8)
        let stop = try JSONDecoder().decode(Stop.self, from: old)
        XCTAssertNil(stop.durationMinutes)
        XCTAssertEqual(stop.scheduleLabel(fallbackHours: 0.75), "06:00 + 约 45 分钟")
        XCTAssertEqual(try JSONValue.wrap(stop), try JSONDecoder().decode(JSONValue.self, from: old))
        var other = stop; other.uid = "other"; other.durationMinutes = 120
        XCTAssertEqual(other.duration(fallbackHours: 0.75), 120)
        XCTAssertEqual(stop.duration(fallbackHours: 0.75), 45)
        XCTAssertEqual(try JSONDecoder().decode(Stop.self, from: JSONEncoder().encode(other)), other)
        let draft = ScheduleDraft(item: other, suggestedHours: 0.75)
        XCTAssertEqual(draft.time, "06:00")
        XCTAssertEqual(draft.durationMinutes, 120)
        var flexible = draft; flexible.isTimed = false; flexible.apply(to: &other)
        XCTAssertEqual(other.time, "")
        XCTAssertNil(other.durationMinutes)
    }

    func testTodayUsesScheduledEndInsteadOfDestinationSuggestion() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        let stop = Stop(uid: "long-visit", place: TestTrip.place, time: "06:00", note: "", durationMinutes: 120)
        plan.days[0].items = [stop]
        let during = DayContext(plan: plan, places: content.catalog.places, now: TestTrip.at(TestTrip.first, "07:59"))
        XCTAssertEqual(during.upcoming.map(\.uid), [stop.uid])
        let ended = DayContext(plan: plan, places: content.catalog.places, now: TestTrip.at(TestTrip.first, "08:00"))
        XCTAssertTrue(ended.upcoming.isEmpty)
        try PlanValidation.validate(plan, catalog: content)
        for minutes in [0, -1, 1441] {
            plan.days[0].items[0].durationMinutes = minutes
            XCTAssertThrowsError(try PlanValidation.validate(plan, catalog: content))
        }
        plan.days[0].items[0].durationMinutes = 120
        plan.days[0].items[0].time = ""
        XCTAssertThrowsError(try PlanValidation.validate(plan, catalog: content))
    }
}
