import XCTest
import SwiftUI
@testable import TripJournal

actor MemoryTripService: TripService {
    var remote: RemoteSnapshot
    var online = true
    var writes = 0
    var pause = false
    var saveContinuation: CheckedContinuation<Void, Never>?
    var startedContinuation: CheckedContinuation<Void, Never>?
    var loseResponse = false
    var expired = false
    var connections = 0
    init(_ plan: TripPlan) { remote = .init(revision: 0, state: plan, updatedAt: 0) }
    func setOnline(_ value: Bool) { online = value }
    func read() -> RemoteSnapshot { remote }
    func writeCount() -> Int { writes }
    func pauseNextSave() { pause = true }
    func waitForSave() async { if saveContinuation != nil { return }; await withCheckedContinuation { startedContinuation = $0 } }
    func resumeSave() { saveContinuation?.resume(); saveContinuation = nil }
    func loseNextResponse() { loseResponse = true }
    func expireSession() { expired = true }
    func connectionCount() -> Int { connections }
    func connect() async throws -> SessionCredentials {
        if !online { throw URLError(.notConnectedToInternet) }
        connections += 1; expired = false
        return .init(cookie: "test", csrf: "test", expiresAt: .greatestFiniteMagnitude)
    }
    func snapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RemoteSnapshot? {
        if !online { throw URLError(.notConnectedToInternet) }
        if expired { throw APIError.unauthorized }
        return since == remote.revision ? nil : remote
    }
    func save(_ plan: TripPlan, revision: Int, credentials: SessionCredentials) async throws -> Int {
        if !online { throw URLError(.notConnectedToInternet) }
        if pause {
            pause = false
            await withCheckedContinuation { continuation in
                saveContinuation = continuation; startedContinuation?.resume(); startedContinuation = nil
            }
        }
        guard revision == remote.revision else { throw APIError.conflict(remote) }
        writes += 1; remote = .init(revision: revision+1, state: plan, updatedAt: Double(writes))
        if loseResponse { loseResponse = false; throw URLError(.timedOut) }
        return remote.revision
    }
    func attachment(_ file: TicketFile, credentials: SessionCredentials, cellular: Bool) async throws -> Data { throw URLError(.fileDoesNotExist) }
    func upload(_ data: Data, type: String, credentials: SessionCredentials) async throws -> TicketFile { throw URLError(.notConnectedToInternet) }
}
actor OfflineTripService: TripService {
    var calls = 0
    nonisolated var isConfigured: Bool { false }
    func connect() async throws -> SessionCredentials { calls += 1; throw URLError(.notConnectedToInternet) }
    func snapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RemoteSnapshot? { calls += 1; return nil }
    func save(_ plan: TripPlan, revision: Int, credentials: SessionCredentials) async throws -> Int { calls += 1; return revision }
    func attachment(_ file: TicketFile, credentials: SessionCredentials, cellular: Bool) async throws -> Data { calls += 1; throw URLError(.fileDoesNotExist) }
    func upload(_ data: Data, type: String, credentials: SessionCredentials) async throws -> TicketFile { calls += 1; throw URLError(.notConnectedToInternet) }
}
@MainActor final class SyncTests: XCTestCase {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func settle(_ stores: [TripStore]) async {
        for _ in 0..<8 { for store in stores { await store.synchronize() }; await Task.yield() }
    }
    func testAutomaticSchedulingAndManualOrderSurviveNotesUndoRestartAndSync() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let localDirectory = try directory()
        let store = try TripStore(content: content, directory: localDirectory, api: service, useKeychain: false)
        store.editingForms = 1
        let five = Stop(uid: "five", place: TestTrip.place, time: "05:00", note: "", durationMinutes: 60)
        let seven = Stop(uid: "seven", place: TestTrip.place, time: "07:00", note: "", durationMinutes: 60)
        let six = Stop(uid: "six", place: TestTrip.place, time: "06:00", note: "", durationMinutes: 120)
        XCTAssertTrue(store.edit { $0.days[0].items = [five, seven] })
        XCTAssertTrue(store.editSchedule { $0.days[0].items.append(six) })
        XCTAssertEqual(store.plan.days[0].items.map(\.uid), ["five", "six", "seven"])
        XCTAssertEqual(store.travelSchedule.events.first { $0.start == TestTrip.at(TestTrip.first, "06:00") }?.end, TestTrip.at(TestTrip.first, "08:00"))

        XCTAssertTrue(store.edit { $0.days[0].items.reverse() })
        XCTAssertEqual(store.plan.days[0].items.map(\.uid), ["seven", "six", "five"])
        XCTAssertTrue(store.editSchedule { $0.days[0].items[1].note = "keep our route" })
        XCTAssertEqual(store.plan.days[0].items.map(\.uid), ["seven", "six", "five"])
        let manual = store.plan
        let restored = try TripStore(content: content, directory: localDirectory, api: service, useKeychain: false)
        XCTAssertEqual(restored.plan, manual)
        XCTAssertTrue(restored.editSchedule { $0.days[0].items[1].time = "04:30" })
        XCTAssertEqual(restored.plan.days[0].items.map(\.uid), ["six", "five", "seven"])
        restored.undo()
        XCTAssertEqual(restored.plan, manual)
        await settle([restored])
        let remote = await service.read()
        XCTAssertEqual(remote.state, manual)
        XCTAssertFalse(restored.pending)
    }

    func testMovingAndDurationEditsSortOnlyTheAffectedDay() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let store = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        store.editingForms = 1
        let stop = Stop(uid: "moving", place: TestTrip.place, time: "06:00", note: "", durationMinutes: 120)
        XCTAssertTrue(store.edit { plan in
            plan.days[0].items = [stop]
            plan.days[1].items = [("late", "07:00"), ("early", "05:00")].map { Stop(uid: $0.0, place: TestTrip.place, time: $0.1, note: "") }
            plan.days[2].items.reverse()
        })
        let untouched = store.plan.days[2]
        XCTAssertTrue(store.editSchedule { plan in
            plan.days[0].items.removeAll { $0.uid == stop.uid }
            plan.days[1].items.append(stop)
        })
        XCTAssertTrue(store.plan.days[0].items.isEmpty)
        XCTAssertEqual(store.plan.days[1].items.map(\.uid), ["early", "moving", "late"])
        XCTAssertEqual(store.plan.days[2], untouched)
        XCTAssertTrue(store.edit { $0.days[1].items.reverse() })
        XCTAssertTrue(store.editSchedule { $0.days[1].items[1].durationMinutes = 90 })
        XCTAssertEqual(store.plan.days[1].items.map(\.uid), ["early", "moving", "late"])
        XCTAssertEqual(store.plan.days[2], untouched)
        XCTAssertTrue(store.edit { $0.days[1].items.reverse() })
        let backup = try JSONEncoder().encode(store.plan)
        try store.importBackup(backup)
        XCTAssertEqual(store.plan.days[1].items.map(\.uid), ["late", "moving", "early"])
    }
    func testTwoOfflineEditorsMergeAfterRestart() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let aDirectory = try directory(), bDirectory = try directory()
        let a = try TripStore(content: content, directory: aDirectory, api: service, useKeychain: false)
        let b = try TripStore(content: content, directory: bDirectory, api: service, useKeychain: false)
        await a.synchronize(); await b.synchronize(); await service.setOnline(false)
        XCTAssertTrue(a.edit { $0.checks["passport"] = true })
        XCTAssertTrue(b.edit { $0.checks["esim"] = true })
        await settle([a,b])
        XCTAssertTrue(a.pending); XCTAssertTrue(b.pending)
        let restored = try TripStore(content: content, directory: aDirectory, api: service, useKeychain: false)
        XCTAssertTrue(restored.pending); XCTAssertEqual(restored.plan.checks["passport"], true)
        await service.setOnline(true); await restored.synchronize(); await settle([restored,b])
        let remote = await service.read()
        XCTAssertEqual(remote.state.checks["passport"], true); XCTAssertEqual(remote.state.checks["esim"], true)
        XCTAssertEqual(restored.plan, b.plan); XCTAssertFalse(restored.pending); XCTAssertFalse(b.pending)
    }
    func testConflictingNotesRequireChoiceAndPreserveDraft() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let a = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        let b = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await a.synchronize(); await b.synchronize(); await service.setOnline(false)
        _ = a.edit { $0.days[0].items[0].note = "A wants lunch" }
        _ = b.edit { $0.days[0].items[0].note = "B wants coffee" }
        await settle([a,b]); await service.setOnline(true)
        await settle([a]); await settle([b])
        XCTAssertTrue(b.hasConflicts); XCTAssertEqual(b.plan.days[0].items[0].note, "B wants coffee")
        let remoteBefore = await service.read()
        XCTAssertEqual(remoteBefore.state.days[0].items[0].note, "A wants lunch")
        b.resolve(Dictionary(uniqueKeysWithValues: b.conflicts.map { ($0.path, MergeChoice.local) }))
        await settle([b,a])
        XCTAssertFalse(b.hasConflicts); XCTAssertEqual(a.plan.days[0].items[0].note, "B wants coffee")
    }
    func testUnchangedPollingDoesNotWriteOrEraseUndo() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let a = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await a.synchronize(); _ = a.edit { $0.checks["passport"] = true }; await settle([a])
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 1); XCTAssertTrue(a.canUndo)
        a.undo(); await settle([a])
        XCTAssertNotEqual(a.plan.checks["passport"], true)
    }
    func testCorruptWorkspaceIsNotReplaced() throws {
        let content = try ContentCatalog.load(), directory = try directory()
        let url = directory.appending(path: "workspace.json")
        let data = Data("broken json".utf8); try data.write(to: url)
        XCTAssertThrowsError(try TripStore(content: content, directory: directory, useKeychain: false))
        XCTAssertEqual(try Data(contentsOf: url), data)
    }
    func testEditWhileSavingIsNotAcknowledgedPrematurely() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let a = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await a.synchronize(); await service.pauseNextSave()
        _ = a.edit { $0.checks["passport"] = true }
        await service.waitForSave()
        _ = a.edit { $0.checks["esim"] = true }
        await service.resumeSave(); await settle([a])
        let remote = await service.read()
        XCTAssertEqual(remote.state.checks["passport"], true); XCTAssertEqual(remote.state.checks["esim"], true)
        XCTAssertFalse(a.pending)
    }
    func testLostSaveResponseDoesNotDuplicateWrite() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let a = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await a.synchronize(); await service.loseNextResponse()
        _ = a.edit { $0.checks["passport"] = true }; await settle([a])
        let writes = await service.writeCount()
        XCTAssertEqual(writes, 1); XCTAssertFalse(a.pending); XCTAssertEqual(a.plan.checks["passport"], true)
    }
    func testExpiredSessionReconnectsWithoutPassword() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let store = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await store.synchronize(); await service.expireSession(); await store.synchronize()
        let connections = await service.connectionCount()
        XCTAssertEqual(connections, 2)
        XCTAssertEqual(store.syncStatus, "已同步"); XCTAssertNotNil(store.lastSyncedAt)
    }
    func testFirstAutomaticSyncPreservesOfflineDraftAndReceivesHotel() async throws {
        let content = try ContentCatalog.load()
        var remote = content.defaults
        var stay = Stay(); stay.name = "First three nights"; stay.checkOut = TestTrip.day(1)
        remote.stays = [stay]
        let service = MemoryTripService(remote)
        await service.setOnline(false)
        let folder = try directory()
        let store = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        _ = store.edit { $0.checks["passport"] = true }
        await settle([store]); XCTAssertTrue(store.pending); XCTAssertNotNil(store.syncFailure)
        let reopened = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        await service.setOnline(true); await settle([reopened])
        XCTAssertEqual(reopened.plan.stays, [stay]); XCTAssertEqual(reopened.plan.checks["passport"], true)
        XCTAssertFalse(reopened.pending); XCTAssertFalse(reopened.hasConflicts)
        XCTAssertNil(reopened.syncFailure); XCTAssertNotNil(reopened.lastSyncedAt)
        let saved = await service.read(); XCTAssertEqual(saved.state, reopened.plan)
        let count = await service.connectionCount(); XCTAssertEqual(count, 1)
    }
    func testManualRefreshRecoversStatusAfterUnchangedResponse() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let store = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await store.synchronize(); await service.setOnline(false); await store.synchronize()
        XCTAssertNotNil(store.syncFailure)
        await service.setOnline(true); await store.synchronize()
        XCTAssertEqual(store.syncStatus, "已同步"); XCTAssertNil(store.syncFailure)
        let count = await service.writeCount(); XCTAssertEqual(count, 0)
    }
    func testEditingPausesAutomaticSyncUntilFormCloses() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let store = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        store.editingForms = 1; await store.synchronize()
        XCTAssertNil(store.lastSyncedAt)
        XCTAssertEqual(store.syncStatus, "编辑完成后自动同步")
        store.editingForms = 0; await store.synchronize(); XCTAssertNotNil(store.lastSyncedAt)
    }
    func testOfflineModeNeverConnectsAndKeepsEditsLocal() async throws {
        let content = try ContentCatalog.load(), service = OfflineTripService()
        let folder = try directory()
        let store = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        XCTAssertFalse(store.isShared)
        XCTAssertEqual(store.syncStatus, TripStore.offlineStatus)
        XCTAssertTrue(store.edit { $0.checks["passport"] = true })
        await settle([store])
        XCTAssertEqual(store.syncStatus, TripStore.offlineStatus)
        XCTAssertNil(store.syncFailure); XCTAssertNil(store.error)
        let calls = await service.calls; XCTAssertEqual(calls, 0)
        let reopened = try TripStore(content: content, directory: folder, api: service, useKeychain: false)
        XCTAssertEqual(reopened.plan.checks["passport"], true)
        XCTAssertEqual(reopened.syncStatus, TripStore.offlineStatus)
        if ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"] == nil { XCTAssertFalse(TripAPI(endpoint: nil).isConfigured) }
    }
    func testUnknownFutureFieldsCannotBeSilentlyDropped() throws {
        let plan = try ContentCatalog.load().defaults
        let raw = try JSONValue.wrap(plan)
        XCTAssertEqual(try PlanCompatibility.decode(raw),plan)
        guard case .object(var object) = raw else { return XCTFail() }
        object["futureField"] = .string("must survive")
        XCTAssertThrowsError(try PlanCompatibility.decode(.object(object)))
    }

    func testSyncIndicatorRecoversAfterUnchangedRemoteRead() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let store = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        XCTAssertFalse(store.syncVerified)
        await store.synchronize()
        XCTAssertTrue(store.syncVerified)
        await service.setOnline(false); await store.synchronize()
        XCTAssertFalse(store.syncVerified)
        await service.setOnline(true); await store.synchronize()
        XCTAssertTrue(store.syncVerified)
        XCTAssertEqual(store.syncStatus, "已同步")
    }

    func testConflictPresentationAndCloudSelection() async throws {
        let content = try ContentCatalog.load(), service = MemoryTripService(try ContentCatalog.load().defaults)
        let a = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        let b = try TripStore(content: content, directory: directory(), api: service, useKeychain: false)
        await a.synchronize(); await b.synchronize(); await service.setOnline(false)
        _ = a.edit { $0.days[0].items[0].note = "先吃午餐，再去花园。" }
        _ = b.edit { $0.days[0].items[0].note = "先回酒店休息，傍晚再出发。" }
        await settle([a, b]); await service.setOnline(true); await settle([a]); await settle([b])
        let conflict = try XCTUnwrap(b.conflicts.first)
        let display = ConflictPresentation(content: content, plans: [b.plan, try XCTUnwrap(b.conflictPlan)])
        XCTAssertTrue(display.title(conflict).contains("备注"))
        XCTAssertFalse(display.title(conflict).contains(b.plan.days[0].items[0].uid))
        XCTAssertEqual(display.rows(conflict).first?.local, "先回酒店休息，傍晚再出发。")
        XCTAssertEqual(display.rows(conflict).first?.remote, "先吃午餐，再去花园。")
        b.resolve([:]); XCTAssertTrue(b.hasConflicts)
        let host = UIHostingController(rootView: NavigationStack { SyncView() }.environment(b))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible()
        host.view.frame = window.bounds; host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot); attachment.name = "Sync conflict comparison"; attachment.lifetime = .keepAlways; add(attachment)
        try screenshot.pngData()?.write(to: URL(fileURLWithPath: "/tmp/trip-sync-conflict.png"))
        window.isHidden = true
        b.resolve(Dictionary(uniqueKeysWithValues: b.conflicts.map { ($0.path, MergeChoice.remote) }))
        await settle([b])
        XCTAssertFalse(b.hasConflicts); XCTAssertFalse(b.pending)
        XCTAssertEqual(b.plan.days[0].items[0].note, "先吃午餐，再去花园。")
    }

    func testDeletedObjectsAndReorderingAreReadable() throws {
        let content = try ContentCatalog.load(), plan = content.defaults
        let display = ConflictPresentation(content: content, plans: [plan])
        let stop = plan.days[0].items[0]
        let deletion = MergeConflict(path: "行程/days/\(plan.days[0].date)/items/\(stop.uid)", local: nil, remote: try .wrap(stop))
        let rows = display.rows(deletion)
        XCTAssertTrue(rows.allSatisfy { $0.local == "已删除" })
        XCTAssertFalse(rows.contains { $0.remote == stop.uid })
        XCTAssertTrue(rows.contains { $0.remote == display.name(stop.place) })
        let note = MergeConflict(path: "行程/note", local: .string("planned"), remote: .string("food"))
        XCTAssertEqual(display.rows(note).first?.local, "planned")
        XCTAssertEqual(display.rows(note).first?.remote, "food")
        let status = MergeConflict(path: "行程/status", local: .string("used"), remote: .string("booked"))
        XCTAssertEqual(display.rows(status).first?.local, "已使用")
        let order = MergeConflict(path: "行程/排序", local: .array([.string(stop.uid)]), remote: .array([]))
        XCTAssertEqual(display.rows(order).first(where: { $0.id == "/0" })?.local, display.name(stop.place))
    }

}
