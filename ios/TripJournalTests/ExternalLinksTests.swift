import XCTest
@testable import TripJournal

final class ExternalLinksTests: XCTestCase {
    @MainActor func testEveryBundledPostKeepsItsNoteIDAndQuery() async throws {
        let posts = try ContentCatalog.load().posts
        XCTAssertFalse(posts.isEmpty)
        XCTAssertEqual(Set(posts.map(\.id)).count, posts.count)
        for post in posts {
            let original = try XCTUnwrap(URL(string: post.url))
            guard let route = ExternalLinks.xiaohongshuNoteURL(original) else {
                // Short links and other platforms are opened unchanged: universal link first, then the browser.
                var attempts: [(URL, Bool)] = []
                let opened = await ExternalLinks.open(original) { candidate, universal in
                    attempts.append((candidate, universal)); return !universal
                }
                XCTAssertTrue(opened)
                XCTAssertEqual(attempts.map(\.0), [original, original])
                XCTAssertEqual(attempts.map(\.1), [true, false])
                continue
            }
            XCTAssertEqual(route.scheme, "xhsdiscover")
            XCTAssertEqual(route.host, "item")
            XCTAssertEqual(route.lastPathComponent, original.lastPathComponent)
            XCTAssertEqual(route.query, original.query)
        }
    }

    func testOnlyKnownPostPathsAndRealPlatformHostsUseTheNoteScheme() throws {
        for source in ["https://www.xiaohongshu.com/discovery/item/0123456789abcdef01234567", "https://xiaohongshu.com/explore/0123456789abcdef01234567"] {
            XCTAssertNotNil(ExternalLinks.xiaohongshuNoteURL(try XCTUnwrap(URL(string: source))))
        }
        for source in ["https://xiaohongshu.com.evil.test/explore/0123456789abcdef01234567", "https://www.xiaohongshu.com/user/profile/0123456789abcdef01234567", "https://www.xiaohongshu.com/explore/invalid", "https://xhslink.com/a/example", "https://booking.example.com/hotels/123.html", "https://www.example.com/"] {
            XCTAssertNil(ExternalLinks.xiaohongshuNoteURL(try XCTUnwrap(URL(string: source))))
        }
    }

    @MainActor func testDirectPostHandoffDoesNotOpenBrowser() async throws {
        let url = try XCTUnwrap(URL(string: "https://www.xiaohongshu.com/explore/0123456789abcdef01234567?source=share&token=a%2Bb%3D"))
        var attempts: [URL] = []
        let opened = await ExternalLinks.open(url) { candidate, universal in
            attempts.append(candidate); XCTAssertFalse(universal); return true
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(attempts.first?.scheme, "xhsdiscover")
    }

    @MainActor func testUnavailableAppFallsBackToTheUnchangedOriginalURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://www.xiaohongshu.com/explore/0123456789abcdef01234567?source=share&token=a%2Bb%3D"))
        var attempts: [(URL, Bool)] = []
        let opened = await ExternalLinks.open(url) { candidate, universal in
            attempts.append((candidate, universal)); return attempts.count == 3
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(attempts.map(\.1), [false, true, false])
        XCTAssertEqual(attempts[1].0, url)
        XCTAssertEqual(attempts[2].0, url)
    }

    @MainActor func testOtherPlatformsTryUniversalLinksBeforeBrowserAndReportFailure() async throws {
        let url = try XCTUnwrap(URL(string: "https://booking.example.com/hotels/123.html?booking=unchanged"))
        var attempts: [Bool] = []
        let opened = await ExternalLinks.open(url) { candidate, universal in
            XCTAssertEqual(candidate, url); attempts.append(universal); return false
        }
        XCTAssertFalse(opened)
        XCTAssertEqual(attempts, [true, false])
    }
}
