import XCTest
@testable import TripJournal

@MainActor final class RouteEnglishAddressTests: XCTestCase {
    private let place = TripConfig.current.destination.addressSuffix, city = TripConfig.current.destination.name
    /// A postcode in the destination's format (trip.json postcodePattern), so these cases run for any destination.
    private func postcode() throws -> String {
        let pattern = try XCTUnwrap(TripConfig.current.destination.postcodePattern, "trip.json has no postcodePattern")
        let candidates = ["12345", "123-4567", "1234", "123456", "12345-6789", "123 45"]
        guard let code = candidates.first(where: { $0.range(of: "^(?:" + pattern + ")$", options: .regularExpression) != nil }) else {
            throw XCTSkip("no sample postcode matches \(pattern)")
        }
        return code
    }
    func testCopyTextPreservesBranchUnitAndPostalAndDeduplicates() throws {
        let code = try postcode()
        let address = RouteEnglishAddress(name: "  Harbor Noodles (Pier)  ", address: "Harbor Noodles (Pier), 12 Pier Road, Unit 5, \(place), \(code), \(place)")
        XCTAssertEqual(address.copyText, "Harbor Noodles (Pier), 12 Pier Road, Unit 5, \(place) \(code)")
        XCTAssertEqual(RouteEnglishAddress(name: "Harbor Lighthouse", address: "Harbor Lighthouse,\n North Shore, \(place)").copyText, "Harbor Lighthouse, North Shore, \(place)")
        XCTAssertEqual(RouteEnglishAddress(name: "Sky Garden", address: "Sky Garden, Central, \(place), \(code), \(place)").copyText, "Sky Garden, Central, \(place) \(code)")
    }
    func testDestinationSuffixPrefixAndLatinAccents() throws {
        let code = try postcode()
        XCTAssertEqual(RouteEnglishAddress(name: "Harbor Inn \(place)", address: "\(city)1 Harbor Front, \(code)").copyText, "Harbor Inn \(place), 1 Harbor Front, \(place) \(code)")
        XCTAssertEqual(RouteEnglishAddress(name: "Café Test", address: "1 Test Road \(place)").copyText, "Café Test, 1 Test Road, \(place)")
        XCTAssertEqual(RouteEnglishAddress(name: "Test", address: "1 Test Road \(place) \(code)").copyText, "Test, 1 Test Road, \(place) \(code)")
    }
    func testRejectsMissingChineseAndNonAddressText() throws {
        let code = try postcode()
        for address in ["", place, "\(place) \(code)", city + "北岸", "https://maps.example.com", "20.0, -150.0"] {
            XCTAssertNil(RouteEnglishAddress(name: "Sky Garden", address: address).copyText, address)
        }
        XCTAssertNil(RouteEnglishAddress(name: "港湾灯塔", address: "Lighthouse Point").copyText)
    }
    func testRepeatedVisitsReuseAddressAndPositionChangesInvalidateIt() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        plan.days[0].items = [Stop(uid: "a", place: TestTrip.place, time: "10:00", note: ""), Stop(uid: "b", place: TestTrip.place, time: "11:00", note: "")]
        var prefs = RoutePreferences(tripID: plan.id)
        let route = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        let node = try XCTUnwrap(route.nodes.first)
        XCTAssertEqual(node.englishAddressKey, route.nodes[1].englishAddressKey)
        let address = RouteEnglishAddress(name: "Harbor Lighthouse", address: "Lighthouse Point, \(place)")
        prefs.values[node.englishAddressKey] = .init(kind: "englishAddress", title: "港湾灯塔 · 英文地址", englishAddress: address)
        let saved = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(saved.legs.map(\.requestKey), route.legs.map(\.requestKey))
        XCTAssertEqual(saved.nodes.map(\.location), route.nodes.map(\.location))
        XCTAssertEqual(saved.nodes[1].englishAddress(in: prefs), address)
        prefs.values[node.locationKey] = .init(kind: "location", title: "新位置", location: .init(name: "中文新地点", address: "新地址", latitude: TestTrip.lat(0.01), longitude: TestTrip.lon(-0.01)))
        let moved = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs).nodes[0]
        XCTAssertNotEqual(moved.englishAddressKey, node.englishAddressKey)
        XCTAssertNil(moved.englishAddress(in: prefs)?.copyText)
        plan.days[0].items[0].place = TestTrip.otherPlace
        let replaced = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs).nodes[0]
        XCTAssertNotEqual(replaced.englishAddressKey, node.englishAddressKey)
    }
    func testHotelEnglishNameAndEndpointReuseEvenWithoutCoordinates() throws {
        let content = try ContentCatalog.load()
        var plan = content.defaults
        let code = try postcode()
        var stay = Stay(); stay.id = "hotel"; stay.name = "测试酒店"; stay.nameEnglish = "Test Hotel"; stay.address = "12 Test Road, \(place) \(code)"
        plan.stays = [stay]
        var prefs = RoutePreferences(tripID: plan.id)
        for start in [true, false] { prefs.values[RoutePreferences.hotelKey(plan.days[0].date, start: start)] = .init(kind: start ? "startHotel" : "endHotel", title: "hotel", value: stay.id) }
        let route = DayRoute(day: plan.days[0], plan: plan, content: content, preferences: prefs)
        XCTAssertEqual(route.nodes.first?.englishAddressKey, route.nodes.last?.englishAddressKey)
        XCTAssertEqual(route.nodes.first?.englishAddress(in: prefs)?.copyText, "Test Hotel, 12 Test Road, \(place) \(code)")
    }
    func testGateOfflineReopenSyncAndAddressConflict() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = AddressTestAPI()
        let store = RoutePreferenceStore(tripID: "trip", directory: directory, api: api)
        let key = "address:test", a = RouteSetting(kind: "englishAddress", title: "酒店 · 英文地址", englishAddress: .init(name: "Hotel A", address: "1 Test Road"))
        XCTAssertFalse(store.set(key, a))
        XCTAssertTrue(store.state.values.isEmpty)
        await api.enable()
        await store.synchronize()
        XCTAssertTrue(store.englishAddressSharing)
        XCTAssertTrue(store.set(key, a))
        let reopened = RoutePreferenceStore(tripID: "trip", directory: directory, api: api)
        XCTAssertTrue(reopened.englishAddressSharing); XCTAssertTrue(reopened.pending)
        XCTAssertEqual(reopened.state.values[key], a)
        await reopened.synchronize()
        XCTAssertFalse(reopened.pending)
        let b = RouteSetting(kind: "englishAddress", title: "酒店 · 英文地址", englishAddress: .init(name: "Hotel B", address: "2 Test Road"))
        XCTAssertTrue(reopened.set(key, b))
        await api.externalAddress(key)
        await reopened.synchronize()
        XCTAssertEqual(reopened.conflicts.count, 1)
        XCTAssertEqual(reopened.conflicts[0].local?.readable, "Hotel B\n2 Test Road")
        reopened.resolve([key: .remote])
        XCTAssertTrue(reopened.conflicts.isEmpty)
        XCTAssertEqual(reopened.state.values[key]?.englishAddress?.name, "Hotel C")
    }
    func testSaveFailureDoesNotPublishNewState() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = AddressTestAPI(); await api.enable()
        let store = RoutePreferenceStore(tripID: "trip", directory: directory, api: api)
        await store.synchronize()
        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(store.set("address:test", .init(kind: "englishAddress", title: "address", englishAddress: .init(name: "Hotel", address: "Test Road"))))
        XCTAssertTrue(store.state.values.isEmpty)
    }
}

private actor AddressTestAPI: RoutePreferenceTransport {
    var enabled = false
    var state = RoutePreferences(tripID: "trip")
    var revision = 0
    func enable() { enabled = true }
    func englishAddressSharing(_ credentials: SessionCredentials) async throws -> Bool { enabled }
    func connect() async throws -> SessionCredentials { .init(cookie: "test", csrf: "test", expiresAt: Date().timeIntervalSince1970 + 3600) }
    func routeSnapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RoutePreferenceSnapshot? { since == revision ? nil : .init(revision: revision, state: state, updatedAt: 0) }
    func saveRoutes(_ state: RoutePreferences, revision: Int, credentials: SessionCredentials) async throws -> Int {
        guard revision == self.revision else { throw RoutePreferenceError.conflict(.init(revision: self.revision, state: self.state, updatedAt: 0)) }
        self.state = state; self.revision += 1; return self.revision
    }
    func externalAddress(_ key: String) { state.values[key] = .init(kind: "englishAddress", title: "酒店 · 英文地址", englishAddress: .init(name: "Hotel C", address: "3 Test Road")); revision += 1 }
}
