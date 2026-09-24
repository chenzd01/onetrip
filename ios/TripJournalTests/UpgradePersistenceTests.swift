import XCTest
@testable import TripJournal

@MainActor final class UpgradePersistenceTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func saved(_ directory: URL) throws -> SavedWorkspace {
        try JSONDecoder().decode(SavedWorkspace.self, from: Data(contentsOf: directory.appending(path: "workspace.json")))
    }
    private func settle(_ store: TripStore) async {
        for _ in 0..<8 { await store.synchronize(); await Task.yield() }
    }
    func testManualContentSurvivesChangedDefaultsAndFirstLogin() async throws {
        let old = try ContentCatalog.load(), directory = try directory()
        let service = MemoryTripService(old.defaults)
        let store = try TripStore(content: old, directory: directory, api: service, useKeychain: false)
        var place = try XCTUnwrap(old.catalog.places.first)
        place.id = "our-custom-stop"; place.name = "Our own stop"
        var stay = Stay(); stay.name = "Our booked hotel"; stay.notes = "Keep this booking"
        XCTAssertTrue(store.edit {
            $0.checks["passport"] = true
            $0.stays = [stay]
            $0.custom.append(place)
            $0.days[0].items.reverse()
            $0.days[0].items.append(.init(uid: "our-stop", place: place.id, time: "14:30", note: "Our chosen time"))
            $0.days[0].note = "Our edited day"
        })
        let expected = store.plan
        XCTAssertEqual(try saved(directory).base, old.defaults)
        var upgraded = old
        // Values matching the new defaults must still be recognized as the user's edits.
        upgraded.defaults = expected
        let reopened = try TripStore(content: upgraded, directory: directory, api: service, useKeychain: false)
        XCTAssertEqual(reopened.plan, expected); XCTAssertTrue(reopened.pending)
        await reopened.synchronize(); await settle(reopened)
        XCTAssertFalse(reopened.hasConflicts); XCTAssertFalse(reopened.pending)
        XCTAssertEqual(reopened.plan, expected)
        let remote = await service.read(); XCTAssertEqual(remote.state, expected)
        let nextLaunch = try TripStore(content: old, directory: directory, api: service, useKeychain: false)
        XCTAssertEqual(nextLaunch.plan, expected); XCTAssertFalse(nextLaunch.pending)
        XCTAssertEqual(try saved(directory).base, expected)
    }
    func testManualUncheckAndDeletionsSurviveUpgradeAndFirstLogin() async throws {
        var old = try ContentCatalog.load()
        let directory = try directory()
        var place = try XCTUnwrap(old.catalog.places.first)
        place.id = "custom-stop-to-remove"; place.name = "Removed custom stop"
        var stay = Stay(); stay.name = "Cancelled hotel"
        old.defaults.checks["passport"] = true
        old.defaults.stays = [stay]
        old.defaults.custom = [place]
        old.defaults.days[0].items = [.init(uid: "stop-to-remove", place: place.id, time: "10:00", note: "Cancelled plan")]
        let service = MemoryTripService(old.defaults)
        let store = try TripStore(content: old, directory: directory, api: service, useKeychain: false)
        XCTAssertTrue(store.edit {
            $0.checks["passport"] = false
            $0.stays = []
            $0.custom = []
            $0.days[0].items = []
        })
        let expected = store.plan
        XCTAssertEqual(try saved(directory).base, old.defaults)
        var upgraded = old; upgraded.defaults = expected
        let reopened = try TripStore(content: upgraded, directory: directory, api: service, useKeychain: false)
        XCTAssertEqual(reopened.plan, expected); XCTAssertTrue(reopened.pending)
        await reopened.synchronize(); await settle(reopened)
        XCTAssertFalse(reopened.hasConflicts); XCTAssertFalse(reopened.pending)
        XCTAssertEqual(reopened.plan.checks["passport"], false)
        XCTAssertEqual(reopened.plan.stays, [])
        XCTAssertTrue(reopened.plan.custom.isEmpty); XCTAssertTrue(reopened.plan.days[0].items.isEmpty)
        XCTAssertEqual(reopened.plan, expected)
        let remote = await service.read(); XCTAssertEqual(remote.state, expected)
        let nextLaunch = try TripStore(content: old, directory: directory, api: service, useKeychain: false)
        XCTAssertEqual(nextLaunch.plan, expected); XCTAssertFalse(nextLaunch.pending)
    }
    func testLegacyDraftRequiresExplicitChoiceWithoutOverwritingEitherSide() async throws {
        let content = try ContentCatalog.load()
        for choice in [MergeChoice.local, .remote] {
            let directory = try directory(), service = MemoryTripService(content.defaults)
            var local = content.defaults; local.checks["passport"] = true
            let original = try JSONEncoder().encode(SavedWorkspace(plan: local, base: nil, revision: nil, pending: true))
            let url = directory.appending(path: "workspace.json"); try original.write(to: url)
            var upgraded = content; upgraded.defaults = local
            let store = try TripStore(content: upgraded, directory: directory, api: service, useKeychain: false)
            await store.synchronize(); await settle(store)
            XCTAssertEqual(store.conflicts.map(\.path), ["整份行程"])
            XCTAssertEqual(store.plan, local); XCTAssertTrue(store.pending)
            XCTAssertEqual(try Data(contentsOf: url), original)
            let before = await service.read(); XCTAssertEqual(before.state, content.defaults)
            store.resolve(["整份行程": choice]); await settle(store)
            let expected = choice == .local ? local : content.defaults
            XCTAssertFalse(store.hasConflicts); XCTAssertFalse(store.pending)
            XCTAssertEqual(store.plan, expected)
            let after = await service.read(); XCTAssertEqual(after.state, expected)
        }
    }
    func testLegacyDraftMatchingRemoteNeedsNoConflict() async throws {
        let content = try ContentCatalog.load(), directory = try directory()
        var local = content.defaults; local.checks["passport"] = true
        try JSONEncoder().encode(SavedWorkspace(plan: local, base: nil, revision: nil, pending: true))
            .write(to: directory.appending(path: "workspace.json"))
        let service = MemoryTripService(local)
        let store = try TripStore(content: content, directory: directory, api: service, useKeychain: false)
        await store.synchronize(); await settle(store)
        XCTAssertFalse(store.hasConflicts); XCTAssertFalse(store.pending)
        XCTAssertEqual(store.plan, local); XCTAssertEqual(try saved(directory).base, local)
        let writes = await service.writeCount(); XCTAssertEqual(writes, 0)
    }
    func testFurtherLegacyEditsDoNotInventBaseline() throws {
        let content = try ContentCatalog.load(), directory = try directory()
        var local = content.defaults; local.checks["passport"] = true
        try JSONEncoder().encode(SavedWorkspace(plan: local, base: nil, revision: nil, pending: true))
            .write(to: directory.appending(path: "workspace.json"))
        let store = try TripStore(content: content, directory: directory, useKeychain: false)
        XCTAssertTrue(store.edit { $0.checks["flight"] = true })
        XCTAssertNil(try saved(directory).base)
    }
    func testFailedSaveDoesNotChangePlanPendingOrUndo() throws {
        let content = try ContentCatalog.load(), directory = try directory()
        let store = try TripStore(content: content, directory: directory, useKeychain: false)
        let url = directory.appending(path: "workspace.json")
        // A nonempty directory at the file destination makes an atomic file replacement fail.
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let marker = Data("must remain".utf8); try marker.write(to: url.appending(path: "marker"))
        XCTAssertFalse(store.edit { $0.checks["passport"] = true })
        XCTAssertEqual(store.plan, content.defaults); XCTAssertFalse(store.pending); XCTAssertFalse(store.canUndo)
        XCTAssertNotNil(store.error); XCTAssertEqual(try Data(contentsOf: url.appending(path: "marker")), marker)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(store.edit { $0.checks["flight"] = true })
        XCTAssertEqual(try saved(directory).base, content.defaults)
        XCTAssertEqual(store.plan.checks["passport"], content.defaults.checks["passport"])
    }
    func testUnknownLocalPlanAndBaseFieldsPreserveOriginalBytes() throws {
        let content = try ContentCatalog.load()
        for key in ["plan", "base"] {
            let directory = try directory()
            let workspace = SavedWorkspace(plan: content.defaults, base: content.defaults, revision: 3, pending: true)
            guard case .object(var raw) = try JSONValue.wrap(workspace), case .object(var plan) = raw[key] else {
                return XCTFail("Expected workspace object")
            }
            plan["futureField"] = .string("must survive"); raw[key] = .object(plan)
            let original = try JSONEncoder().encode(JSONValue.object(raw)), url = directory.appending(path: "workspace.json")
            try original.write(to: url)
            XCTAssertThrowsError(try TripStore(content: content, directory: directory, useKeychain: false))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }
}
