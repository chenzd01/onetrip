import XCTest
@testable import TripJournal

@MainActor final class HTTPIntegrationTests: XCTestCase {
    func testTwoRouteClientsMergeAndResolveWithoutAlteringItinerary() async throws {
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"], let endpoint = URL(string: raw), endpoint.host == "127.0.0.1" else { throw XCTSkip("Requires isolated loopback server") }
        let firstAPI = TripAPI(endpoint: endpoint, accessKey: String(repeating: "t", count: 48))
        let credentials = try await firstAPI.connect()
        let originalRead = try await firstAPI.snapshot(credentials, since: nil)
        let original = try XCTUnwrap(originalRead)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = RoutePreferenceStore(tripID: original.state.id, directory: directory.appending(path: "a"), api: firstAPI)
        let b = RoutePreferenceStore(tripID: original.state.id, directory: directory.appending(path: "b"), api: TripAPI(endpoint: endpoint, accessKey: String(repeating: "t", count: 48)))
        await a.synchronize(); await b.synchronize()
        a.set("test-a", .init(kind: "mode", title: "第一段", value: "driving"))
        b.set("test-b", .init(kind: "mode", title: "第二段", value: "driving"))
        await a.synchronize(); await b.synchronize(); await a.synchronize()
        XCTAssertEqual(a.state, b.state); XCTAssertTrue(b.conflicts.isEmpty)
        a.set("test-a", nil)
        b.set("test-a", .init(kind: "mode", title: "第一段", value: "walking"))
        await a.synchronize(); await b.synchronize()
        XCTAssertEqual(b.conflicts.map(\.id), ["test-a"])
        b.resolve(["test-a": .remote])
        XCTAssertTrue(b.conflicts.isEmpty); XCTAssertNil(b.state.values["test-a"])
        let after = try await firstAPI.snapshot(credentials, since: nil)
        XCTAssertEqual(after?.revision, original.revision); XCTAssertEqual(after?.state, original.state)
    }
    func testIndependentRoutePreferencesOverHTTP() async throws {
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"], let endpoint = URL(string: raw), endpoint.host == "127.0.0.1" else { throw XCTSkip("Requires isolated loopback server") }
        let api = TripAPI(endpoint: endpoint, accessKey: String(repeating: "t", count: 48))
        let credentials = try await api.connect()
        let original = try await api.snapshot(credentials, since: nil)
        let first = try await api.routeSnapshot(credentials, since: nil)
        let snapshot = try XCTUnwrap(first)
        var settings = snapshot.state
        settings.values["test-mode"] = .init(kind: "mode", title: "本机集成测试", value: "driving")
        let revision = try await api.saveRoutes(settings, revision: snapshot.revision, credentials: credentials)
        let unchanged = try await api.routeSnapshot(credentials, since: revision)
        XCTAssertNil(unchanged)
        do {
            _ = try await api.saveRoutes(snapshot.state, revision: snapshot.revision, credentials: credentials)
            XCTFail("Expected independent route conflict")
        } catch RoutePreferenceError.conflict(let latest) { XCTAssertEqual(latest.state, settings) }
        let after = try await api.snapshot(credentials, since: nil)
        XCTAssertEqual(after?.state, original?.state); XCTAssertEqual(after?.revision, original?.revision)
    }
    func testDiningRoundTripAndTwoClientReservationConflict() async throws {
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"], let endpoint = URL(string: raw), endpoint.host == "127.0.0.1" else {
            throw XCTSkip("Run with isolated loopback server and TRIP_INTEGRATION_URL")
        }
        let a = TripAPI(endpoint: endpoint, accessKey: String(repeating: "t", count: 48))
        let b = TripAPI(endpoint: endpoint, accessKey: String(repeating: "t", count: 48))
        let ca = try await a.connect(), cb = try await b.connect()
        let read = try await a.snapshot(ca, since: nil)
        let initial = try XCTUnwrap(read)
        var plan = initial.state
        let diningID = try XCTUnwrap(try ContentCatalog.load().catalog.places.first { $0.isDining }?.id)
        let meal = Stop(uid: UUID().uuidString.lowercased(), place: diningID, time: "", note: "Local integration fixture",
                        meal: MealPlan(kind: "lunch", reservation: DiningReservation(status: "planned")))
        plan.days[0].items.append(meal)
        let firstRevision = try await a.save(plan, revision: initial.revision, credentials: ca)
        let secondRead = try await b.snapshot(cb, since: nil)
        let shared = try XCTUnwrap(secondRead)
        XCTAssertEqual(shared.state.days[0].items.last, meal)
        XCTAssertEqual(shared.state.budget, initial.state.budget)
        var local = shared.state, remote = shared.state
        let index = local.days[0].items.count - 1
        local.days[0].items[index].meal?.reservation.notes = "Device A dietary note"
        remote.days[0].items[index].meal?.reservation.notes = "Device B dietary note"
        _ = try await a.save(local, revision: firstRevision, credentials: ca)
        do {
            _ = try await b.save(remote, revision: firstRevision, credentials: cb)
            XCTFail("Concurrent reservation writes must not overwrite each other")
        } catch APIError.conflict(let latest) {
            let result = PlanMerge.merge(base: try JSONValue.wrap(shared.state), local: try JSONValue.wrap(remote), remote: try JSONValue.wrap(latest.state))
            XCTAssertEqual(result.conflicts.count, 1)
            let presentation = ConflictPresentation(content: try ContentCatalog.load(), plans: [remote, latest.state])
            XCTAssertTrue(presentation.title(try XCTUnwrap(result.conflicts.first)).contains("预约"))
            XCTAssertEqual(latest.state.days[0].items[index].meal?.reservation.notes, "Device A dietary note")
        }
    }

    func testActualServerCookieCSRFRevisionAndOriginalAttachment() async throws {
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"], let endpoint = URL(string:raw), endpoint.host == "127.0.0.1" else {
            throw XCTSkip("Run with isolated loopback server and TRIP_INTEGRATION_URL")
        }
        let a = TripAPI(endpoint:endpoint, accessKey: String(repeating: "t", count: 48)), b = TripAPI(endpoint:endpoint, accessKey: String(repeating: "t", count: 48))
        let ca = try await a.connect(), cb = try await b.connect()
        XCTAssertFalse(ca.csrf.isEmpty)
        let initialRead = try await a.snapshot(ca,since:nil)
        let initial = try XCTUnwrap(initialRead)
        let unchanged = try await a.snapshot(ca,since:initial.revision)
        XCTAssertNil(unchanged)
        var plan = initial.state; plan.checks["passport"] = !(plan.checks["passport"] ?? false)
        plan.days[0].items[0].time = "06:00"
        plan.days[0].items[0].durationMinutes = 120
        var invalid = ca; invalid.csrf = "incorrect"
        do { _ = try await a.save(plan,revision:initial.revision,credentials:invalid); XCTFail("Missing CSRF protection") }
        catch APIError.response(let code,_) { XCTAssertEqual(code,403) }
        let revision = try await a.save(plan,revision:initial.revision,credentials:ca)
        do { _ = try await b.save(initial.state,revision:initial.revision,credentials:cb); XCTFail("Stale writes must conflict") }
        catch APIError.conflict(let remote) { XCTAssertEqual(remote.revision,revision); XCTAssertEqual(remote.state,plan) }
        let directory = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = try TripStore(content:ContentCatalog.load(),directory:directory,api:a,useKeychain:false)
        await store.synchronize()
        let bytes = Data("%PDF-1.4\nIsolated original fixture\n%%EOF".utf8)
        let source = directory.appending(path:"original.pdf"); try bytes.write(to:source)
        let file = try await store.attachments.importFile(source)
        var ticket = Ticket(); ticket.title = "Isolated integration ticket"; ticket.files = [file]
        XCTAssertTrue(store.edit { $0.tickets = [TestTrip.otherPlace:[ticket]] })
        for _ in 0..<30 {
            await store.synchronize()
            if !store.pending { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        XCTAssertFalse(store.pending,store.syncStatus)
        let savedRead = try await b.snapshot(cb,since:nil)
        let saved = try XCTUnwrap(savedRead)
        XCTAssertEqual(saved.state.days[0].items[0].durationMinutes, 120)
        XCTAssertEqual(saved.state.tickets?[TestTrip.otherPlace]?.first?.files.first?.id,file.id)
        let downloaded = try await b.attachment(file,credentials:cb,cellular:true)
        XCTAssertEqual(downloaded,bytes)
        let reopened = try TripStore(content:ContentCatalog.load(),directory:directory,api:a,useKeychain:false)
        let reopenedData = try await reopened.attachments.data(for:file)
        XCTAssertEqual(reopenedData,bytes)
        var expired = ca; expired.cookie = "trip_session=expired"
        do { _ = try await a.snapshot(expired,since:nil); XCTFail("Invalid sessions must fail") }
        catch APIError.unauthorized { }
    }
}
