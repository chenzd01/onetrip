import XCTest
import CryptoKit
@testable import TripJournal

final class CoreTests: XCTestCase {
    func testDestinationGuidesSurviveCatalogDecodingAndLegacyPlacesStillLoad() throws {
        let content = try ContentCatalog.load()
        let place = try XCTUnwrap(content.catalog.places.first { !($0.guides ?? []).isEmpty })
        let guides = try XCTUnwrap(place.guides)
        XCTAssertEqual(Set(guides.map(\.id)).count, guides.count)
        for guide in guides {
            XCTAssertFalse(guide.sections.isEmpty)
            XCTAssertTrue(guide.sections.allSatisfy { !$0.title.isEmpty && !$0.paragraphs.isEmpty })
            XCTAssertTrue(guide.links.allSatisfy { URL(string: $0.url)?.scheme == "https" })
        }
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as? [String: Any])
        legacy.removeValue(forKey: "guides")
        let decoded = try JSONDecoder().decode(Place.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.guides)
        XCTAssertEqual(decoded.name, place.name)
    }
    func testBundledContentIsDecodableAndValid() throws {
        let content = try ContentCatalog.load()
        XCTAssertFalse(content.catalog.places.isEmpty)
        XCTAssertEqual(Set(content.catalog.places.map(\.id)).count, content.catalog.places.count)
        XCTAssertEqual(content.trip.id, TripConfig.current.id)
        XCTAssertEqual(content.defaults.id, content.trip.id)
        XCTAssertEqual(content.catalog.days.map(\.date), TripConfig.current.dayKeys)
        XCTAssertEqual(content.defaults.days.map(\.date), TripConfig.current.dayKeys)
        XCTAssertFalse(content.preparation.isEmpty)
        XCTAssertEqual(Set(content.preparation.map(\.id)).count, content.preparation.count)
        XCTAssertTrue(content.posts.allSatisfy { !($0.summary ?? "").isEmpty || !($0.body ?? "").isEmpty })
        XCTAssertTrue(content.posts.allSatisfy { !$0.platform.isEmpty })
        let phrases = content.phrases.flatMap(\.items)
        XCTAssertFalse(phrases.isEmpty)
        XCTAssertEqual(Set(phrases.map(\.id)).count, phrases.count)
        XCTAssertTrue(phrases.allSatisfy { !$0.native.isEmpty && !$0.local.isEmpty })
        try PlanValidation.validate(content.defaults, catalog: content)
        for post in content.posts { for image in post.images { XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(ContentCatalog.resource(image.path)).path)) } }
    }
    func testEveryBundledResourceMatchesManifestWithoutNetwork() throws {
        struct Entry: Decodable { var path: String; var bytes: Int; var sha256: String }
        let manifest = try XCTUnwrap(ContentCatalog.resource("manifest.json"))
        let entries = try JSONDecoder().decode([Entry].self,from:Data(contentsOf:manifest))
        XCTAssertFalse(entries.isEmpty)
        for entry in entries {
            try autoreleasepool {
                let url = try XCTUnwrap(ContentCatalog.resource(entry.path))
                let bytes = try Data(contentsOf:url,options:.mappedIfSafe)
                XCTAssertEqual(bytes.count,entry.bytes,entry.path)
                XCTAssertEqual(SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),entry.sha256,entry.path)
            }
        }
    }
    func testIndependentFieldsMergeAndSameFieldConflicts() throws {
        let base: JSONValue = .object(["checks": .object(["passport": .bool(false), "hotel": .bool(false)]), "note": .string("base")])
        let local: JSONValue = .object(["checks": .object(["passport": .bool(true), "hotel": .bool(false)]), "note": .string("local")])
        let remote: JSONValue = .object(["checks": .object(["passport": .bool(false), "hotel": .bool(true)]), "note": .string("remote")])
        let result = PlanMerge.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(result.conflicts.map(\.path), ["行程/note"])
        let resolved = PlanMerge.merge(base: base, local: local, remote: remote, choices: ["行程/note": .remote])
        XCTAssertTrue(resolved.conflicts.isEmpty)
        XCTAssertEqual(resolved.value, .object(["checks": .object(["passport": .bool(true), "hotel": .bool(true)]), "note": .string("remote")]))
    }
    func testDeleteEditConflictIsNotLost() {
        let item: JSONValue = .object(["id": .string("a"), "note": .string("base")])
        let edited: JSONValue = .object(["id": .string("a"), "note": .string("new")])
        let result = PlanMerge.merge(base: .array([item]), local: .array([]), remote: .array([edited]))
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertNil(result.conflicts[0].local)
        let resolved = PlanMerge.merge(base: .array([item]), local: .array([]), remote: .array([edited]), choices: ["行程/a": .remote])
        XCTAssertEqual(resolved.value, .array([edited]))
    }
    func testTimezoneDoesNotUseDeviceLocalDate() throws {
        XCTAssertEqual(TripClock.calendar.timeZone.identifier, TripConfig.current.timezone)
        // Both ends of the first trip day, built independently in the destination zone: a calendar that used
        // the device zone would put one of them on a neighbouring day.
        var zoned = Calendar(identifier: .gregorian); zoned.timeZone = try XCTUnwrap(TimeZone(identifier: TripConfig.current.timezone))
        let first = TestTrip.first, parts = first.split(separator: "-").compactMap { Int($0) }
        let late = try XCTUnwrap(zoned.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 23, minute: 30)))
        let early = try XCTUnwrap(zoned.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 0, minute: 30)))
        for utc in [late, early] {
            XCTAssertEqual(TripClock.dayKey(utc), first)
        }
        XCTAssertEqual(TripClock.date(first + "T23:30"), late)
        XCTAssertNil(TripClock.date(String(first.prefix(8)) + "32"))
    }
    func testIndependentNewOptionalCollectionsMerge() {
        let base: JSONValue = .object([:])
        let local: JSONValue = .object(["tickets": .object(["harbor-light": .array([.string("a")])])])
        let remote: JSONValue = .object(["tickets": .object(["maritime-museum": .array([.string("b")])])])
        let result = PlanMerge.merge(base: base, local: local, remote: remote)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.value, .object(["tickets": .object(["harbor-light": .array([.string("a")]), "maritime-museum": .array([.string("b")])])]))
    }
}

// Dates derived from the bundled trip so tests follow content/trip.json.
enum TestTrip {
    static var first: String { TripConfig.current.startDate }
    static var last: String { TripConfig.current.endDate }
    static func day(_ offset: Int, from key: String = TripConfig.current.startDate) -> String {
        TripClock.dayKey(TripClock.calendar.date(byAdding: .day, value: offset, to: TripClock.date(key)!)!)
    }
    static func at(_ key: String, _ time: String) -> Date { TripClock.date(key + "T" + time)! }
    /// Coordinates offset from trip.json's map centre, so they stay inside the destination bounds.
    static func lat(_ offset: Double = 0) -> Double { TripConfig.current.map.center[0] + offset }
    static func lon(_ offset: Double = 0) -> Double { TripConfig.current.map.center[1] + offset }
    /// Located, non-dining places from the bundled content, so these tests keep passing after content/ is replaced.
    static var place: String { located[0] }
    static var otherPlace: String { located[1] }
    private static let located: [String] = {
        let content = try! ContentCatalog.load()
        return content.catalog.places.filter { !$0.isDining && content.locations[$0.id]?.coordinates.count == 2 }.map(\.id)
    }()
}
