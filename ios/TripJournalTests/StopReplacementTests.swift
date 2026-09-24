import XCTest
@testable import TripJournal

@MainActor final class StopReplacementTests: XCTestCase {
    func testDiningReplacementDoesNotTransferReservation() throws {
        let content = try ContentCatalog.load()
        let dining = try XCTUnwrap(content.catalog.places.first { $0.isDining })
        let ordinary = try XCTUnwrap(content.catalog.places.first { !$0.isDining })
        var plan = content.defaults
        let item = Stop(uid: "reserved-meal", place: dining.id, time: "12:00", note: "预约保留", durationMinutes: 60, meal: MealPlan(reservation: DiningReservation(status: "booked", date: plan.days[0].date, time: "12:00", reference: "TEST-RESERVATION")))
        plan.days[0].items = [item]
        let original = plan
        XCTAssertThrowsError(try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: ordinary))
        XCTAssertEqual(plan, original)
        var other = item; other.place = ordinary.id; other.meal = nil
        plan.days[0].items = [other]
        XCTAssertThrowsError(try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: other, destination: dining))
    }

    func testReplacementPreservesIdentityScheduleNotesAndOrder() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        let old = content.catalog.places[0]
        let destination = content.catalog.places[1]
        let item = Stop(uid: "replacement-test", place: old.id, time: "13:15", note: "原备注", durationMinutes: 90)
        plan.days[0].items.insert(item, at: 0)
        let result = try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: destination)
        var expected = item
        expected.place = destination.id
        XCTAssertEqual(result.days[0].items[0], expected)
        XCTAssertEqual(result.days[0].items.map(\.uid), plan.days[0].items.map(\.uid))
        XCTAssertEqual(result.days[0].date, plan.days[0].date)
        XCTAssertEqual(result.days.dropFirst().map(\.items), plan.days.dropFirst().map(\.items))
        try PlanValidation.validate(result, catalog: content)
    }

    func testFreezesLegacyTimedDurationButKeepsUntimedArrangementUntimed() throws {
        let content = try ContentCatalog.load()
        let old = try XCTUnwrap(content.catalog.places.first { $0.hours > 0 })
        let destination = try XCTUnwrap(content.catalog.places.first { $0.id != old.id })
        for time in ["12:00", ""] {
            var plan = content.defaults
            let item = Stop(uid: "legacy-duration", place: old.id, time: time, note: "")
            plan.days[0].items = [item]
            let result = try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: destination)
            XCTAssertEqual(result.days[0].items[0].time, time)
            XCTAssertEqual(result.days[0].items[0].durationMinutes, time.isEmpty ? nil : Int((old.hours * 60).rounded()))
            try PlanValidation.validate(result, catalog: content)
        }
    }

    func testNewCustomPlaceAndReplacementAreOnePlanChange() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        let old = content.catalog.places[0]
        let item = Stop(uid: "new-custom", place: old.id, time: "12:00", note: "保留", durationMinutes: 60)
        plan.days[0].items = [item]
        var destination = old
        destination.id = "new-custom-place"
        destination.name = "新咖啡馆"
        let result = try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: destination, isNewCustom: true)
        XCTAssertEqual(result.custom.last?.id, destination.id)
        XCTAssertEqual(result.days[0].items[0].place, destination.id)
        XCTAssertFalse(plan.custom.contains { $0.id == destination.id })
        try PlanValidation.validate(result, catalog: content)
        XCTAssertThrowsError(try StopReplacement.applying(to: result, catalog: content.catalog.places, item: item, destination: destination, isNewCustom: true))
    }

    func testMissingStopOrDestinationAndInvalidLegacyDurationFailWithoutMutation() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        var old = content.catalog.places[0]
        old.id = "zero-duration"
        old.hours = 0
        plan.custom.append(old)
        let item = Stop(uid: "invalid-duration", place: old.id, time: "12:00", note: "")
        plan.days[0].items = [item]
        let original = plan
        let destination = content.catalog.places[1]
        XCTAssertThrowsError(try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: destination))
        var missing = item
        missing.uid = "missing"
        XCTAssertThrowsError(try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: missing, destination: destination))
        var absent = destination
        absent.id = "absent"
        XCTAssertThrowsError(try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: absent))
        XCTAssertEqual(plan, original)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func settle(_ stores: [TripStore]) async {
        for _ in 0..<8 {
            for store in stores { await store.synchronize() }
            await Task.yield()
        }
    }

    func testStoreReplacementSurvivesRestartAndUndoRestoresCustomCollection() async throws {
        let content = try ContentCatalog.load()
        let service = MemoryTripService(content.defaults)
        await service.setOnline(false)
        let folder = try directory()
        let store = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        store.editingForms = 1
        let item = Stop(uid: "persist-replacement", place: content.catalog.places[0].id, time: "14:00", note: "保留备注", durationMinutes: 75)
        XCTAssertTrue(store.edit { $0.days[0].items = [item] })
        let before = store.plan
        var destination = content.catalog.places[1]
        destination.id = "persist-new-place"
        destination.name = "新建测试地点"
        XCTAssertTrue(store.replacePlace(for: item, with: destination, isNewCustom: true))
        let replacement = store.plan
        XCTAssertTrue(store.pending)
        let restored = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        restored.editingForms = 1
        XCTAssertEqual(restored.plan, replacement)
        XCTAssertTrue(restored.pending)
        XCTAssertEqual(restored.plan.custom.last?.id, destination.id)
        store.undo()
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(store.plan.custom, before.custom)
        let afterUndo = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        afterUndo.editingForms = 1
        XCTAssertEqual(afterUndo.plan, before)
    }

    func testStoreWriteFailureLeavesExistingAndNewPlaceReplacementUnchanged() async throws {
        let content = try ContentCatalog.load()
        let service = MemoryTripService(content.defaults)
        await service.setOnline(false)
        let folder = try directory()
        let store = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        store.editingForms = 1
        let item = Stop(uid: "write-failure", place: content.catalog.places[0].id, time: "12:00", note: "", durationMinutes: 60)
        XCTAssertTrue(store.edit { $0.days[0].items = [item] })
        let before = store.plan
        let pendingBefore = store.pending
        let workspace = folder.appending(path: "workspace.json")
        try FileManager.default.removeItem(at: workspace)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        let destination = content.catalog.places[1]
        XCTAssertFalse(store.replacePlace(for: item, with: destination))
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(store.pending, pendingBefore)
        XCTAssertNotNil(store.error)
        var custom = destination
        custom.id = "failed-new-place"
        XCTAssertFalse(store.replacePlace(for: item, with: custom, isNewCustom: true))
        XCTAssertEqual(store.plan, before)
        XCTAssertEqual(store.plan.custom, before.custom)
    }

    func testStoreInvalidCustomReplacementDoesNotLeaveAnOrphan() async throws {
        let content = try ContentCatalog.load()
        let service = MemoryTripService(content.defaults)
        await service.setOnline(false)
        let folder = try directory()
        let store = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        store.editingForms = 1
        let item = Stop(uid: "invalid-custom", place: content.catalog.places[0].id, time: "12:00", note: "", durationMinutes: 60)
        XCTAssertTrue(store.edit { $0.days[0].items = [item] })
        let before = store.plan
        var custom = content.catalog.places[1]
        custom.id = "invalid-new-place"
        custom.budget = -1
        XCTAssertFalse(store.replacePlace(for: item, with: custom, isNewCustom: true))
        XCTAssertEqual(store.plan, before)
        XCTAssertNotNil(store.error)
        let restored = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        restored.editingForms = 1
        XCTAssertEqual(restored.plan, before)
    }

    func testStoreConflictsPreventExistingAndNewPlaceReplacement() async throws {
        let content = try ContentCatalog.load()
        let service = MemoryTripService(content.defaults)
        let a = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        let b = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await a.synchronize()
        await b.synchronize()
        await service.setOnline(false)
        XCTAssertTrue(a.edit { $0.days[0].items[0].note = "对方修改" })
        XCTAssertTrue(b.edit { $0.days[0].items[0].note = "本机修改" })
        await settle([a, b])
        await service.setOnline(true)
        await settle([a])
        await settle([b])
        XCTAssertTrue(b.hasConflicts)
        let before = b.plan
        let item = b.plan.days[0].items[0]
        let destination = try XCTUnwrap(content.catalog.places.first { $0.id != item.place })
        XCTAssertFalse(b.replacePlace(for: item, with: destination))
        XCTAssertEqual(b.plan, before)
        var custom = destination
        custom.id = "conflicted-new-place"
        XCTAssertFalse(b.replacePlace(for: item, with: custom, isNewCustom: true))
        XCTAssertEqual(b.plan, before)
        XCTAssertTrue(b.hasConflicts)
        XCTAssertEqual(b.error, "请先处理共享冲突，本机草稿已保留")
    }

}
