import XCTest
@testable import TripJournal

final class DayContextTests: XCTestCase {
    func testPreparationDueDatesComeFromContent() throws {
        let preparation = try ContentCatalog.load().preparation
        XCTAssertTrue(preparation.contains { $0.dueDate == nil })
        XCTAssertTrue(preparation.contains { $0.dueDate != nil })
        for prep in preparation {
            guard let due = prep.dueDate else { XCTAssertTrue(prep.isDue(on: "2000-01-01"), prep.id); continue }
            XCTAssertNotNil(TripClock.date(due), prep.id)
            XCTAssertFalse(prep.isDue(on: TestTrip.day(-1, from: due)), prep.id)
            XCTAssertTrue(prep.isDue(on: due), prep.id)
            XCTAssertTrue(prep.isDue(on: TestTrip.day(1, from: due)), prep.id)
        }
        let legacy = try JSONDecoder().decode(Preparation.self, from: Data(#"{"id":"x","group":"g","title":"t","summary":"s","body":[],"links":[]}"#.utf8))
        XCTAssertNil(legacy.dueDate); XCTAssertTrue(legacy.isDue(on: TestTrip.first))
    }

    func testPreparationHidesUntilNextPendingDayAndReappearsAtMidnight() throws {
        let preparation = try ContentCatalog.load().preparation
        let latest = try XCTUnwrap(preparation.filter { $0.dueDate != nil }.max { $0.dueDate! < $1.dueDate! })
        let due = try XCTUnwrap(latest.dueDate), always = try XCTUnwrap(preparation.first { $0.dueDate == nil }).id
        var checks = Dictionary(uniqueKeysWithValues: preparation.map { ($0.id, $0.id != latest.id) })
        func pending(_ date: Date) -> [String] {
            let day = TripClock.dayKey(date)
            return preparation.filter { $0.isDue(on: day) && checks[$0.id] != true }.map(\.id)
        }
        XCTAssertTrue(pending(TestTrip.at(TestTrip.day(-1, from: due), "23:59")).isEmpty)
        XCTAssertEqual(pending(TestTrip.at(due, "00:00")), [latest.id])
        checks[latest.id] = true
        XCTAssertTrue(pending(TestTrip.at(due, "12:00")).isEmpty)
        checks[always] = false
        XCTAssertEqual(pending(TestTrip.at(due, "12:00")), [always])
        checks.removeValue(forKey: always)
        XCTAssertEqual(pending(TestTrip.at(due, "12:00")), [always])
    }

    func testLocalMidnightAndTripPhases() throws {
        let c = try ContentCatalog.load(), p = c.defaults
        XCTAssertEqual(DayContext(plan:p,places:c.catalog.places,now:TestTrip.at(TestTrip.day(-1), "23:59")).phase, .before)
        XCTAssertEqual(DayContext(plan:p,places:c.catalog.places,now:TestTrip.at(TestTrip.first, "00:00")).day?.date, TestTrip.first)
        XCTAssertEqual(DayContext(plan:p,places:c.catalog.places,now:TestTrip.at(TestTrip.day(1, from: TestTrip.last), "00:00")).phase, .after)
    }
    func testUpcomingDurationFlexibleTicketsAndCheckout() throws {
        let c = try ContentCatalog.load(); var p = c.defaults
        var place = c.catalog.places[0]; place.hours = 2
        p.days[0].items = [.init(uid:"past",place:place.id,time:"08:00",note:""), .init(uid:"ongoing",place:place.id,time:"11:00",note:""), .init(uid:"future",place:place.id,time:"14:00",note:""), .init(uid:"flex",place:place.id,time:"",note:"")]
        var stay = Stay(); stay.name = "Hotel"; stay.checkOut = TestTrip.first; p.stays = [stay]
        var ticket = Ticket(); ticket.title = "Ticket"; ticket.date = TestTrip.first; p.tickets = [place.id:[ticket]]
        let context = DayContext(plan:p,places:[place],now:TestTrip.at(TestTrip.first, "12:00"))
        XCTAssertEqual(context.upcoming.map(\.uid), ["ongoing","future"])
        XCTAssertEqual(context.flexible.map(\.uid), ["flex"])
        XCTAssertEqual(context.ticketPlaces, [place.id]); XCTAssertTrue(context.tonight.isEmpty); XCTAssertEqual(context.checkingOut.count,1)
        p.days[0].items = []
        XCTAssertEqual(DayContext(plan:p,places:[place],now:TestTrip.at(TestTrip.first, "12:00")).ticketPlaces,[place.id])
    }
    func testWidgetTransitionsDoNotKeepYesterdaysPlan() throws {
        let start = TestTrip.at(TestTrip.first, "10:00"), end = TestTrip.at(TestTrip.first, "12:00")
        let schedule = TravelSchedule(events: [.init(title:"花园",start:start,end:end,time:"10:00")],dayKeys:[TestTrip.first,TestTrip.day(1),TestTrip.last])
        XCTAssertEqual(schedule.snapshot(at:start).title,"花园")
        XCTAssertNotEqual(schedule.snapshot(at:end).title,"花园")
        XCTAssertNotEqual(schedule.snapshot(at:TripClock.date(TestTrip.day(1))!).title,"花园")
        XCTAssertTrue(schedule.transitions(after:start).contains(end))
        XCTAssertTrue(schedule.transitions(after:start).contains(TripClock.date(TestTrip.day(1, from: TestTrip.last))!))
        let before = schedule.snapshot(at: TestTrip.at(TestTrip.day(-1), "12:00"))
        XCTAssertEqual(before.subtitle, WidgetSnapshot.tripSubtitle)
        XCTAssertTrue(before.subtitle.contains(TripConfig.current.destination.name))
    }

}
