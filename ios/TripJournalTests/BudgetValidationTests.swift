import XCTest
@testable import TripJournal

final class BudgetValidationTests: XCTestCase {
    private let home = TripConfig.current.currency.home, local = TripConfig.current.currency.local
    func testTripTotalsAreStoredWithoutMultipliers() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        for index in plan.days.indices { plan.days[index].items = [] }
        plan.budget = .init(flightOut: 1000, flightReturn: 900, hotel: 500, food: 200, transport: 100, other: 30)
        let lines = BudgetCalculator.lines(budget: plan.budget)
        XCTAssertEqual(lines.first { $0.id == "hotel" }?.amount, 500)
        XCTAssertEqual(lines.first { $0.id == "food" }?.amount, 200)
        XCTAssertEqual(lines.first { $0.id == "transport" }?.amount, 100)
        XCTAssertNil(lines.first { $0.id == "tickets" })
        XCTAssertEqual(lines.map(\.id), ["flightOut", "flightReturn", "hotel", "food", "transport", "other"])
        XCTAssertEqual(lines.filter { $0.currency == home }.map(\.id), home == local ? lines.map(\.id) : ["flightOut", "flightReturn"])
        XCTAssertEqual(lines.reduce(0) { $0 + $1.converted(to: home, rate: 5) }, home == local ? 2730 : 1900 + 830 * 5)
        try PlanValidation.validate(plan, catalog: content)
    }
    func testEditingTotalsInEitherCurrencyAndSwitchingDoesNotDrift() throws {
        try XCTSkipIf(home == local, "Sample trip uses two currencies")
        var budget = try ContentCatalog.load().defaults.budget
        budget.hotel = 123.456789; budget.food = 12.3456789; budget.transport = 9.87654321
        let rate = 5.123456
        var draft = BudgetDraft(budget: budget, currency: home, rate: rate)
        for _ in 0..<50 { try draft.changeCurrency(to: local); try draft.changeCurrency(to: home) }
        var saved = try draft.resolvedBudget()
        XCTAssertEqual(saved.hotel, budget.hotel)
        XCTAssertEqual(saved.food, budget.food)
        XCTAssertEqual(saved.transport, budget.transport)
        draft.setText("2500", for: "hotel")
        draft.setText("1000", for: "food")
        try draft.changeCurrency(to: local)
        draft.setText("300", for: "transport")
        draft.setText("80.50", for: "other")
        draft.setText("400", for: "flightOut")
        saved = try draft.resolvedBudget()
        let lines = BudgetCalculator.lines(budget: saved)
        XCTAssertEqual(try XCTUnwrap(lines.first { $0.id == "hotel" }).converted(to: home, rate: rate), 2500, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(lines.first { $0.id == "food" }).converted(to: home, rate: rate), 1000, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(lines.first { $0.id == "transport" }).amount, 300, accuracy: 0.000001)
        XCTAssertEqual(saved.other, 80.5)
        XCTAssertEqual(saved.flightOut, 400 * rate, accuracy: 0.000001)
        let reopened = BudgetDraft(budget: saved, currency: local, rate: rate)
        XCTAssertEqual(reopened.texts["transport"], "300")
        XCTAssertEqual(reopened.texts["other"], "80.5")
    }
    func testInvalidInputKeepsCurrencyAndDraftAndBlankMeansZero() throws {
        try XCTSkipIf(home == local, "Sample trip uses two currencies")
        let budget = try ContentCatalog.load().defaults.budget
        var draft = BudgetDraft(budget: budget, currency: home, rate: 5)
        draft.setText("-1", for: "hotel")
        XCTAssertThrowsError(try draft.changeCurrency(to: local))
        XCTAssertEqual(draft.currency, home)
        XCTAssertEqual(draft.texts["hotel"], "-1")
        XCTAssertEqual(draft.budget, budget)
        for invalid in ["NaN", "inf", "1.2.3", "一百"] {
            draft.setText(invalid, for: "hotel")
            XCTAssertThrowsError(try draft.resolvedBudget())
        }
        draft.setText("", for: "hotel")
        XCTAssertEqual(try draft.resolvedBudget().hotel, 0)
        draft.setText("12,50", for: "other")
        XCTAssertEqual(try draft.resolvedBudget().other, 2.5)
        draft.setText(String(Int(PlanValidation.maximumBudget) * 10), for: "flightOut")
        XCTAssertThrowsError(try draft.resolvedBudget())
    }
    func testInvalidSharedValuesCannotBecomePendingDraft() throws {
        let c = try ContentCatalog.load()
        let place = try XCTUnwrap(c.catalog.places.first).id
        var plan = c.defaults
        var ticket = Ticket(); ticket.title = "Museum"; ticket.time = "25:00"
        plan.tickets = [place:[ticket]]
        XCTAssertThrowsError(try PlanValidation.validate(plan,catalog:c))
        ticket.time = "12:30"; ticket.deadline = "2030-04-31T12:00"; plan.tickets = [place:[ticket]]
        XCTAssertThrowsError(try PlanValidation.validate(plan,catalog:c))
        plan.tickets = [:]; plan.budget.hotel = .infinity
        XCTAssertThrowsError(try PlanValidation.validate(plan,catalog:c))
        plan.budget.hotel = PlanValidation.maximumBudget + 1
        XCTAssertThrowsError(try PlanValidation.validate(plan,catalog:c))
        plan = c.defaults; var a = Stay(); a.name = "First"; a.checkOut = TestTrip.day(1); var b = Stay(); b.name = "Second"; b.checkIn = TestTrip.first; plan.stays = [a,b]
        XCTAssertThrowsError(try PlanValidation.validate(plan,catalog:c))
        b.checkIn = TestTrip.day(1); plan.stays = [a,b]
        XCTAssertNoThrow(try PlanValidation.validate(plan,catalog:c))
        for (checkIn, checkOut) in [(TestTrip.day(-1, from: TripConfig.current.stayRange.first), TestTrip.first), (TestTrip.first, TestTrip.day(1, from: TestTrip.last)), ("2030-5-01", TestTrip.last)] {
            var stay = Stay(); stay.name = "Outside"; stay.checkIn = checkIn; stay.checkOut = checkOut; plan.stays = [stay]
            XCTAssertThrowsError(try PlanValidation.validate(plan,catalog:c), checkIn + "…" + checkOut)
        }
    }
    func testStayDefaultsAndDueDatesComeFromTripConfig() {
        let stay = Stay()
        XCTAssertEqual(stay.checkIn, TripConfig.current.stayRange.first)
        XCTAssertEqual(stay.checkOut, TripConfig.current.stayRange.last)
        XCTAssertEqual(Ticket().quantity, TripConfig.current.partySize)
        XCTAssertEqual(DiningReservation().partySize, TripConfig.current.partySize)
    }
}
