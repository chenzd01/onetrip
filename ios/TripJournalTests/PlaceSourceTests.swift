import XCTest
@testable import TripJournal

final class PlaceSourceTests: XCTestCase {
    func testKnownSources() throws {
        let cases: [(String, PlaceSource)] = [
            ("https://www.parks.example.gov/visit", .publicInformation),
            ("https://www.transport.gov.xs/", .publicInformation),
            ("https://example.com/sample-food-guide/", .reference),
            ("https://www.xiaohongshu.com/explore/0123456789abcdef01234567?source=share#note", .xiaohongshu),
            ("https://xhslink.com/a/123", .xiaohongshu),
            ("https://WWW.PARKS.EXAMPLE.GOV/", .publicInformation)
        ]
        for (raw, expected) in cases { XCTAssertEqual(PlaceSource.classify(try XCTUnwrap(URL(string: raw))), expected, raw) }
    }
    func testUnknownAndLookalikeHostsAreNotOfficial() throws {
        for raw in [
            "https://example.com/parks.example.gov",
            "https://www.gov.example.com/",
            "https://fakegov.example.com/",
            "https://www.parks.example.gov@evil.example/",
            "https://www.xiaohongshu.com.example.com/",
            "https://example.com/?url=https://www.xiaohongshu.com/",
            "ftp://www.parks.example.gov/"
        ] { XCTAssertEqual(PlaceSource.classify(try XCTUnwrap(URL(string: raw))), .reference, raw) }
    }
}
