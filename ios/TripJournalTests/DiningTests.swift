import XCTest
@testable import TripJournal

final class DiningTests: XCTestCase {
    private func fixture() throws -> (ContentCatalog, TripPlan, Stop) {
        var content = try ContentCatalog.load()
        var place = try XCTUnwrap(content.catalog.places.first)
        place.id = "dining-test-fixture"; place.name = "测试餐厅"; place.kind = "餐饮"; place.hours = 2; place.budget = 0
        content.catalog.places.append(place)
        var plan = content.defaults
        for index in plan.days.indices { plan.days[index].items = [] }
        let stop = Stop(uid: "our-dinner", place: place.id, time: "19:00", note: "", durationMinutes: 120,
                        meal: MealPlan(kind: "dinner", reservation: DiningReservation(status: "booked", date: plan.days[0].date, time: "19:00", partySize: 2, reference: "demo-only")))
        plan.days[0].items = [stop]
        return (content, plan, stop)
    }

    func testOldStopsRoundTripWithoutInsertingNewFields() throws {
        let raw = Data(#"{"uid":"legacy","place":"harbor-noodles","time":"","note":"keep"}"#.utf8)
        let stop = try JSONDecoder().decode(Stop.self, from: raw)
        XCTAssertNil(stop.meal)
        XCTAssertEqual(try JSONValue.wrap(stop), try JSONDecoder().decode(JSONValue.self, from: raw))
    }

    func testNewMealsRoundTripAndValidation() throws {
        let (content, plan, stop) = try fixture()
        XCTAssertEqual(try PlanCompatibility.decode(JSONValue.wrap(plan)), plan)
        try PlanValidation.validate(plan, catalog: content)
        var changed = plan
        for status in ["planned", "notRequired", "cancelled"] {
            changed.days[0].items[0].meal?.reservation = DiningReservation(status: status)
            try PlanValidation.validate(changed, catalog: content)
        }
        changed.days[0].items[0] = stop
        changed.days[0].items[0].meal?.reservation.time = ""
        XCTAssertThrowsError(try PlanValidation.validate(changed, catalog: content))
        changed.days[0].items[0] = stop
        changed.days[0].items[0].meal?.reservation.partySize = 21
        XCTAssertThrowsError(try PlanValidation.validate(changed, catalog: content))
        changed.days[0].items[0] = stop
        changed.days[0].items[0].place = TestTrip.place
        XCTAssertThrowsError(try PlanValidation.validate(changed, catalog: content))
    }

    func testRepeatedRestaurantVisitsKeepSeparateBookingsAndMerge() throws {
        let (_, base, stop) = try fixture()
        var two = base
        var second = stop; second.uid = "second-dinner"; second.meal?.reservation.reference = "second-booking"
        second.meal?.reservation.date = two.days[1].date
        two.days[1].items = [second]
        var local = two, remote = two
        local.days[0].items[0].meal?.reservation.notes = "First visit allergy request"
        remote.days[1].items[0].meal?.reservation.partySize = 3
        let merged = PlanMerge.merge(base: try JSONValue.wrap(two), local: try JSONValue.wrap(local), remote: try JSONValue.wrap(remote))
        XCTAssertTrue(merged.conflicts.isEmpty)
        let value = try merged.value.decode(TripPlan.self)
        XCTAssertEqual(value.days[0].items[0].meal?.reservation.notes, "First visit allergy request")
        XCTAssertEqual(value.days[1].items[0].meal?.reservation.partySize, 3)
        XCTAssertEqual(value.days[1].items[0].meal?.reservation.reference, "second-booking")
    }

    func testReservationConflictsAreReadableAndNoFieldsAreLost() throws {
        let (content, base, _) = try fixture()
        var local = base, remote = base
        local.days[0].items[0].meal?.reservation.status = "notRequired"
        remote.days[0].items[0].meal?.reservation.status = "cancelled"
        let result = PlanMerge.merge(base: try JSONValue.wrap(base), local: try JSONValue.wrap(local), remote: try JSONValue.wrap(remote))
        let conflict = try XCTUnwrap(result.conflicts.first)
        let presentation = ConflictPresentation(content: content, plans: [local, remote])
        XCTAssertTrue(presentation.title(conflict).contains("餐厅预约"))
        let row = try XCTUnwrap(presentation.rows(conflict).first)
        XCTAssertEqual(row.local, "无需预约")
        XCTAssertEqual(row.remote, "已取消")
    }

    func testMovedBookedDinnerPreservesActualReservationAndWarns() throws {
        let (content, plan, stop) = try fixture()
        let venue = content.dining?.venue(stop.place)
        let changedDay = plan.days[1]
        let warnings = DiningSchedule.warnings(item: stop, day: changedDay, places: content.catalog.places, venue: venue)
        XCTAssertTrue(warnings.contains { $0.contains("预约不同") })
        XCTAssertEqual(stop.meal?.reservation.date, plan.days[0].date)
        var edited = stop; edited.time = "18:00"
        XCTAssertTrue(edited.meal!.reservation.differs(from: edited, day: plan.days[0].date))
    }

    func testMealOverlapAndTodayDuration() throws {
        let (content, plan, stop) = try fixture()
        var day = plan.days[0]
        day.items.append(Stop(uid: "show", place: TestTrip.place, time: "20:00", note: "", durationMinutes: 45))
        XCTAssertTrue(DiningSchedule.warnings(item: stop, day: day, places: content.catalog.places, venue: nil).contains { $0.contains("重叠") })
        let context = DayContext(plan: plan, places: content.catalog.places, now: TripClock.date(day.date + "T20:30")!)
        XCTAssertTrue(context.upcoming.contains { $0.uid == stop.uid })
        XCTAssertFalse(DayContext(plan: plan, places: content.catalog.places, now: TripClock.date(day.date + "T21:00")!).upcoming.contains { $0.uid == stop.uid })
    }

    func testDinnerRecommendationNeverUsesLunchOnlyPrice() throws {
        var venue = try XCTUnwrap(ContentCatalog.load().dining?.restaurants.first)
        let lunch = DiningMenu(name: "Lunch", meal: "lunch", price: 100, basis: "perPerson", tax: "nett", includes: "Food", sourceURL: "https://example.com/menu", checkedAt: "2030-04-01")
        var dinner = lunch; dinner.meal = "dinner"; dinner.price = 200
        venue.menus = [lunch, dinner]
        XCTAssertEqual(venue.referenceMenu(for: "dinner")?.price, 200)
        venue.menus = [lunch]
        XCTAssertNil(venue.referenceMenu(for: "dinner"))
        dinner.meal = "any"; venue.menus.append(dinner)
        XCTAssertEqual(venue.referenceMenu(for: "dinner")?.price, 200)
        XCTAssertEqual(venue.referenceMenu()?.price, 100)
    }

    func testExceptionalClosuresWarnEvenOnNormallyOpenDates() throws {
        let (content, plan, stop) = try fixture()
        var venue = try XCTUnwrap(content.dining?.restaurants.first)
        venue.closedWeekdays = []
        venue.closedDates = [plan.days[0].date]
        XCTAssertTrue(DiningSchedule.isClosed(venue, on: plan.days[0].date))
        XCTAssertFalse(DiningSchedule.isClosed(venue, on: plan.days[1].date))
        XCTAssertTrue(DiningSchedule.warnings(item: stop, day: plan.days[0], places: content.catalog.places, venue: venue).contains { $0.contains("休息日") })
    }

    func testPricesRequireExplicitTaxBasisAndDoNotChangeBudget() throws {
        var menu = DiningMenu(name: "Lunch", meal: "lunch", price: 100, basis: "perPerson", tax: "++", includes: "Food only", sourceURL: "https://example.com/menu", checkedAt: "2030-04-01")
        XCTAssertNil(menu.totalPerPerson)
        menu.serviceChargePercent = 10; menu.taxPercent = 9
        XCTAssertEqual(try XCTUnwrap(menu.totalPerPerson), 119.9, accuracy: 0.0001)
        menu.tax = "nett"
        XCTAssertEqual(menu.totalPerPerson, 100)
        menu.basis = "perDish"
        XCTAssertNil(menu.totalPerPerson)
        let (content, plan, _) = try fixture()
        XCTAssertEqual(plan.budget, content.defaults.budget)
        XCTAssertEqual(BudgetCalculator.lines(budget: plan.budget).map(\.amount), BudgetCalculator.lines(budget: content.defaults.budget).map(\.amount))
    }

    func testEditingReservationKeepsManualOrderAndMovePreservesOtherMeals() throws {
        let (_, initial, dinner) = try fixture()
        var plan = initial
        let first = Stop(uid: "first", place: TestTrip.place, time: "21:00", note: "manual first")
        let last = Stop(uid: "last", place: TestTrip.place, time: "11:00", note: "manual last")
        plan.days[0].items = [first, dinner, last]
        var changed = dinner; changed.meal?.reservation.notes = "confirmed dietary needs"
        DiningSchedule.apply(changed, to: &plan, day: 0)
        XCTAssertEqual(plan.days[0].items.map(\.uid), [first.uid, dinner.uid, last.uid])
        XCTAssertEqual(plan.days[0].items[1].time, dinner.time)
        XCTAssertEqual(plan.days[0].items[1].durationMinutes, dinner.durationMinutes)
        DiningSchedule.apply(changed, to: &plan, day: 1)
        XCTAssertEqual(plan.days[0].items, [first, last])
        XCTAssertEqual(plan.days[1].items, [changed])
        XCTAssertEqual(plan.days[1].items[0].meal?.reservation.date, initial.days[0].date)
    }
}
