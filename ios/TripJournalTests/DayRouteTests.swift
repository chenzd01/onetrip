import XCTest
import MapKit
@testable import TripJournal

@MainActor final class DayRouteTests: XCTestCase {
    func testMapGroupsRepeatedCoordinatesWithoutLosingVisitIdentity() {
        let location = RouteLocation(name: "酒店", address: "Test", latitude: TestTrip.lat(), longitude: TestTrip.lon())
        let other = RouteLocation(name: "景点", address: "Test", latitude: TestTrip.lat(0.01), longitude: TestTrip.lon(0.01))
        let nodes = [
            RouteNode(id: "start", locationKey: "hotel", name: "酒店", query: "", time: "出发酒店", location: location),
            RouteNode(id: "stop", locationKey: "place", name: "景点", query: "", time: "10:00", location: other),
            RouteNode(id: "end", locationKey: "hotel", name: "酒店", query: "", time: "返回酒店", location: location)
        ]
        let groups = RouteMapGroup.groups(for: nodes)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].label, "1·3")
        XCTAssertEqual(groups[0].stops.map(\.id), ["start", "end"])
        XCTAssertEqual(groups[0].stops.map { $0.node.time }, ["出发酒店", "返回酒店"])
        XCTAssertEqual(groups[1].label, "2")
    }
    func testMapGroupsKeepTimelineNumbersForMissingPositionsAndDistinctEntrances() {
        let location = RouteLocation(name: "入口一", address: "Test", latitude: TestTrip.lat(), longitude: TestTrip.lon())
        let nearby = RouteLocation(name: "入口二", address: "Test", latitude: TestTrip.lat(0.00001), longitude: TestTrip.lon())
        let nodes = [
            RouteNode(id: "missing", locationKey: "a", name: "待确认", query: "", time: "09:00"),
            RouteNode(id: "a", locationKey: "b", name: "入口一", query: "", time: "10:00", location: location),
            RouteNode(id: "b", locationKey: "c", name: "入口二", query: "", time: "11:00", location: nearby)
        ]
        let groups = RouteMapGroup.groups(for: nodes)
        XCTAssertEqual(groups.map(\.label), ["2", "3"])
        XCTAssertNotEqual(groups[0].id, groups[1].id)
        XCTAssertTrue(RouteMapGroup.groups(for: []).isEmpty)
    }
    func testServerPolylineDecodingRejectsTruncationAndBadRegion() throws {
        func encode(_ points: [(Int, Int)]) -> String {
            var previous = (0, 0), bytes: [UInt8] = []
            for point in points {
                for delta in [point.0 - previous.0, point.1 - previous.1] {
                    var value = delta < 0 ? ~(delta << 1) : delta << 1
                    while value >= 32 { bytes.append(UInt8((value & 31) | 32) + 63); value >>= 5 }
                    bytes.append(UInt8(value) + 63)
                }
                previous = point
            }
            return String(bytes: bytes, encoding: .utf8)!
        }
        let map = TripConfig.current.map, micro = { (value: Double) in Int((value * 1_000_000).rounded()) }
        let lat = micro(map.center[0]), lon = micro(map.center[1])
        var response = RoadRouteResponse(shape: encode([(lat + 18_000, lon - 30_000), (lat + 5_000, lon - 10_000)]), precision: 6,
                                         distance: 1230, seconds: 912, calculatedAt: 1_700_000_000, source: "Valhalla / OpenStreetMap")
        let points = try response.coordinates()
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1].latitude, Double(lat + 5_000) / 1_000_000, accuracy: 0.000001)
        XCTAssertEqual(points[0].longitude, Double(lon - 30_000) / 1_000_000, accuracy: 0.000001)
        response.shape.removeLast()
        XCTAssertThrowsError(try response.coordinates())
        let outside = (micro(map.bounds.maxLat + 1), micro(map.bounds.maxLon + 1))
        response.shape = encode([outside, (outside.0 + 100, outside.1 + 100)])
        XCTAssertThrowsError(try response.coordinates())
        response.precision = 5
        XCTAssertThrowsError(try response.coordinates())
    }
    func testTimeOrderFlexibleMissingAndReplacementIdentity() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        let missing = Place(id: "unknown-point", name: "自由活动", en: "", zone: "", kind: "自定义", hours: 1, budget: 0, desc: "", tip: "", travel: "", rain: "", food: "", link: "")
        plan.custom.append(missing)
        plan.days[0].items = [Stop(uid: "b", place: TestTrip.place, time: "14:00", note: ""), Stop(uid: "a", place: "unknown-point", time: "10:00", note: ""), Stop(uid: "f", place: TestTrip.place, time: "", note: ""), Stop(uid: "c", place: TestTrip.place, time: "14:00", note: "")]
        var prefs = RoutePreferences(tripID: plan.id)
        let route = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(route.nodes.compactMap(\.stopID), ["a", "b", "c"])
        XCTAssertEqual(route.flexible.map(\.uid), ["f"])
        XCTAssertNil(route.legs[0].requestKey)
        XCTAssertNotNil(route.legs[1].requestKey)
        XCTAssertNotEqual(route.nodes[1].id, route.nodes[2].id)
        prefs.values[route.legs[0].id] = .init(kind: "mode", title: "drive", value: "driving")
        plan.days[0].items[1].place = TestTrip.place
        let replaced = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertFalse(replaced.legs[0].driving)
        XCTAssertNotEqual(route.legs[0].id, replaced.legs[0].id)
        let previous = replaced.legs.map(\.requestKey)
        plan.days[0].items[0].note = "only a note"
        XCTAssertEqual(DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs).legs.map(\.requestKey), previous)
    }
    func testConfirmedLocationAndDeletedHotel() throws {
        let content = try ContentCatalog.load(), plan = content.defaults
        var prefs = RoutePreferences(tripID: plan.id)
        prefs.values[RoutePreferences.hotelKey(plan.days[0].date, start: true)] = .init(kind: "startHotel", title: "old", value: "deleted")
        let route = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(route.warnings.count, 1)
        let node = try XCTUnwrap(route.nodes.first)
        let location = RouteLocation(name: "confirmed", address: "Test", latitude: TestTrip.lat(), longitude: TestTrip.lon())
        prefs.values[node.locationKey] = .init(kind: "location", title: "confirmed", location: location)
        let updated = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(updated.nodes.first?.location, location)
    }
    func testHotelEndpointsAndTimeEditsChangeOnlyAdjacentLegs() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        var stay = Stay(); stay.id = "test-hotel"; stay.name = "测试酒店"; stay.address = "Test address"
        plan.stays = [stay]
        plan.days[0].items = [Stop(uid: "a", place: TestTrip.place, time: "10:00", note: ""), Stop(uid: "b", place: TestTrip.place, time: "11:00", note: "")]
        var prefs = RoutePreferences(tripID: plan.id)
        for start in [true, false] {
            prefs.values[RoutePreferences.hotelKey(plan.days[0].date, start: start)] = .init(kind: start ? "startHotel" : "endHotel", title: "hotel", value: stay.id)
        }
        let route = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(route.nodes.count, 4); XCTAssertEqual(route.legs.count, 3)
        XCTAssertNil(route.nodes[0].location); XCTAssertNil(route.legs[0].requestKey)
        XCTAssertEqual(route.nodes[0].locationKey, route.nodes[3].locationKey)
        XCTAssertNotEqual(route.nodes[0].id, route.nodes[3].id)
        prefs.values[route.legs[1].id] = .init(kind: "mode", title: "a to b", value: "driving")
        plan.days[0].items[0].time = "12:00"
        let reordered = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(reordered.nodes.compactMap(\.stopID), ["b", "a"])
        XCTAssertFalse(reordered.legs[1].driving)
        XCTAssertEqual(plan.days[0].items.count, 2)
    }
    func testNoPathErrorIsNotMisreportedAsOffline() {
        let error = APIError.response(422, "未找到可通行路线，请核对入口")
        XCTAssertTrue(DayRouteService.failureMessage(error).contains("核对入口"))
        XCTAssertEqual(DayRouteService.duration(0), "0 分钟")
    }
    func testMergeTreatsLocationAsAtomicAndPreservesIndependentChanges() {
        let base = RoutePreferences(tripID: "trip")
        var a = base, b = base
        a.values["one"] = .init(kind: "mode", title: "one", value: "driving")
        b.values["two"] = .init(kind: "mode", title: "two", value: "walking")
        let (merged, conflicts) = RoutePreferenceMerge.merge(base: base, local: a, remote: b)
        XCTAssertEqual(merged.values.count, 2); XCTAssertTrue(conflicts.isEmpty)
        a.values["point"] = .init(kind: "location", title: "point", location: .init(name: "A", address: "A", latitude: TestTrip.lat(), longitude: TestTrip.lon()))
        b.values["point"] = .init(kind: "location", title: "point", location: .init(name: "B", address: "B", latitude: TestTrip.lat(0.02), longitude: TestTrip.lon(0.02)))
        let (_, locationConflicts) = RoutePreferenceMerge.merge(base: base, local: a, remote: b)
        XCTAssertEqual(locationConflicts.map(\.id), ["point"])
        let (resolved, remaining) = RoutePreferenceMerge.merge(base: base, local: a, remote: b, choices: ["point": .remote])
        XCTAssertTrue(remaining.isEmpty); XCTAssertEqual(resolved.values["point"], b.values["point"])
    }
    func testRouteStoreOfflineReopenAndConflictResolution() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = RouteTestAPI()
        let store = RoutePreferenceStore(tripID: "trip", directory: directory, api: api)
        XCTAssertTrue(store.set("mode", .init(kind: "mode", title: "A → B", value: "driving")))
        let reopened = RoutePreferenceStore(tripID: "trip", directory: directory, api: api)
        XCTAssertEqual(reopened.state, store.state); XCTAssertTrue(reopened.pending)
        await reopened.synchronize()
        XCTAssertFalse(reopened.pending)
        reopened.set("mode", .init(kind: "mode", title: "A → B", value: "walking"))
        await api.externalChange()
        await reopened.synchronize()
        XCTAssertEqual(reopened.conflicts.count, 1)
        XCTAssertEqual(reopened.state.values["mode"]?.value, "walking")
        reopened.resolve(["mode": .remote])
        XCTAssertTrue(reopened.conflicts.isEmpty)
        XCTAssertNil(reopened.state.values["mode"])
    }
    func testCorruptArchiveIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "route-preferences.json"), bytes = Data("invalid".utf8)
        try bytes.write(to: file)
        let store = RoutePreferenceStore(tripID: "trip", directory: directory, api: RouteTestAPI())
        XCTAssertFalse(store.set("mode", .init(kind: "mode", title: "x", value: "walking")))
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testServiceCoalescesLimitsConcurrencyAndKeepsPartialResults() async throws {
        let calculator = RouteTestCalculator()
        let service = DayRouteService(calculator: calculator)
        let legs = (0..<4).map { testLeg($0) }
        let one = UUID(), two = UUID()
        service.observe(legs, consumer: one); service.observe(legs, consumer: two)
        try await Task.sleep(for: .seconds(1.3))
        XCTAssertEqual(calculator.calls, 4)
        XCTAssertLessThanOrEqual(calculator.peak, 2)
        XCTAssertEqual(service.results.count, 3)
        XCTAssertEqual(service.failures.count, 1)
        service.release(one)
        service.observe(legs, consumer: two)
        try await Task.sleep(for: .milliseconds(550))
        XCTAssertEqual(calculator.calls, 4)
        service.release(two)
    }
    func testCancelledRequestsNeverPublishStaleResults() async throws {
        let calculator = RouteTestCalculator()
        let service = DayRouteService(calculator: calculator), consumer = UUID()
        let old = testLeg(0), next = testLeg(1)
        service.observe([old], consumer: consumer)
        try await Task.sleep(for: .milliseconds(540))
        service.observe([next], consumer: consumer)
        try await Task.sleep(for: .seconds(1))
        XCTAssertNil(service.result(for: old)); XCTAssertNotNil(service.result(for: next))
        service.release(consumer)
    }
    func testSameCoordinateNeedsNoNetworkAndIsZeroDistance() async throws {
        var leg = testLeg(0); leg.to.location = leg.from.location
        let result = try await ServerRouteCalculator().calculate(leg)
        XCTAssertEqual(result.distance, 0); XCTAssertEqual(result.seconds, 0)
    }
    func testLiveServerWalkingAndDrivingWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["TRIP_LIVE_ROUTES"] == "1", TripAPI.isConfigured else { throw XCTSkip("Live regional routing is an opt-in acceptance gate") }
        let content = try ContentCatalog.load()
        let known = content.locations.sorted { $0.key < $1.key }.prefix(2).map(\.value)
        guard known.count == 2 else { throw XCTSkip("Needs two bundled locations") }
        let places = try await TripAPI().searchRoutePlaces(known[1].name)
        XCTAssertTrue(places.contains { $0.valid })
        var leg = testLeg(0)
        leg.from.location = .init(name: known[0].name, address: known[0].address, latitude: known[0].coordinates[0], longitude: known[0].coordinates[1])
        leg.to.location = .init(name: known[1].name, address: known[1].address, latitude: known[1].coordinates[0], longitude: known[1].coordinates[1])
        for driving in [false, true] {
            leg.driving = driving
            let started = Date()
            let result = try await ServerRouteCalculator().calculate(leg)
            XCTAssertGreaterThan(result.distance, 0); XCTAssertGreaterThan(result.seconds, 0); XCTAssertGreaterThan(result.polyline.pointCount, 1)
            print("LIVE_ROUTE mode=\(driving ? "driving" : "walking") meters=\(result.distance) travelSeconds=\(result.seconds) calculationSeconds=\(Date().timeIntervalSince(started))")
        }
    }
    private func testLeg(_ index: Int) -> RouteLeg {
        let a = RouteNode(id: "a\(index)", locationKey: "a", name: "A", query: "A", time: "10:00", location: .init(name: "A", address: "Test", latitude: TestTrip.lat(Double(index) * 0.001), longitude: TestTrip.lon()))
        var b = a; b.id = "b\(index)"; b.location?.longitude = TestTrip.lon(0.01)
        return RouteLeg(id: "\(index)", from: a, to: b, driving: false)
    }
}
@MainActor private final class RouteTestCalculator: RouteCalculating {
    var calls = 0, active = 0, peak = 0
    func calculate(_ leg: RouteLeg) async throws -> RouteResult {
        calls += 1; active += 1; peak = max(peak, active)
        defer { active -= 1 }
        // Deliberately ignores cancellation to exercise the service's stale-result guard.
        try? await Task.sleep(for: .milliseconds(150))
        if leg.id == "3" { throw TripError.message("offline") }
        return RouteResult(polyline: MKPolyline(), distance: 120, seconds: 90, calculatedAt: .now)
    }
}
private actor RouteTestAPI: RoutePreferenceTransport {
    var state = RoutePreferences(tripID: "trip")
    var revision = 0
    func connect() async throws -> SessionCredentials { .init(cookie: "test", csrf: "test", expiresAt: Date().timeIntervalSince1970 + 3600) }
    func routeSnapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RoutePreferenceSnapshot? {
        since == revision ? nil : .init(revision: revision, state: state, updatedAt: 0)
    }
    func saveRoutes(_ state: RoutePreferences, revision: Int, credentials: SessionCredentials) async throws -> Int {
        guard revision == self.revision else { throw RoutePreferenceError.conflict(.init(revision: self.revision, state: self.state, updatedAt: 0)) }
        self.state = state; self.revision += 1; return self.revision
    }
    func externalChange() { state.values["mode"] = nil; revision += 1 }
}
