import XCTest
@testable import TripJournal

final class ReminderTests: XCTestCase {
    func testReminderRebuildFollowsMoveDeletionAndDeadlineWithoutPrivateContent() throws {
        let c = try ContentCatalog.load(); var p = c.defaults
        let place = try XCTUnwrap(c.catalog.places.first { !$0.isDining }).id
        let stop = Stop(uid:"reminder-test",place:place,time:"10:00",note:"PRIVATE NOTE")
        p.days[0].items = [stop]; p.days[1].items = []
        var ticket = Ticket(); ticket.title = "PRIVATE TICKET"; ticket.reference = "PRIVATE CODE"; ticket.date = p.days[0].date; ticket.time = "12:00"; ticket.deadline = TestTrip.day(-1) + "T12:00"
        p.tickets = [place:[ticket]]
        let initial = ReminderPlanner.candidates(plan:p,content:c)
        XCTAssertTrue(initial.allSatisfy { !$0.safeBody.contains("PRIVATE") })
        let preferences = ["stop-reminder-test":30]
        let scheduled = ReminderPlanner.scheduled(initial,preferences:preferences,now:TestTrip.at(TestTrip.day(-2), "00:00"))
        XCTAssertEqual(scheduled.count,1); XCTAssertEqual(scheduled[0].1,TestTrip.at(TestTrip.first, "09:30"))
        p.days[0].items = []; p.days[1].items = [stop]
        XCTAssertEqual(ReminderPlanner.scheduled(ReminderPlanner.candidates(plan:p,content:c),preferences:preferences,now:TestTrip.at(TestTrip.day(-2), "00:00"))[0].1,TestTrip.at(TestTrip.day(1), "09:30"))
        p.days[1].items = []
        XCTAssertTrue(ReminderPlanner.scheduled(ReminderPlanner.candidates(plan:p,content:c),preferences:preferences,now:TestTrip.at(TestTrip.day(-2), "00:00")).isEmpty)
        ticket.status = "cancelled"; p.tickets = [place:[ticket]]
        XCTAssertFalse(ReminderPlanner.candidates(plan:p,content:c).contains { $0.id == "ticket-" + ticket.id || $0.id == "deadline-" + ticket.id })
    }
}
