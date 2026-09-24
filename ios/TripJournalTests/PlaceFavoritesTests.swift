import XCTest
@testable import TripJournal

@MainActor final class PlaceFavoritesTests: XCTestCase {
    func testFavoritesPersistLocallyAndDoNotShareAcrossStores() throws {
        let name = "place-favorites-tests-" + UUID().uuidString
        let otherName = name + "-other-device"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let other = try XCTUnwrap(UserDefaults(suiteName: otherName))
        defer {
            defaults.removePersistentDomain(forName: name)
            other.removePersistentDomain(forName: otherName)
        }
        let favorites = PlaceFavorites(defaults: defaults)
        favorites.toggle("maritime-museum")
        favorites.toggle("my-custom-place")
        XCTAssertTrue(PlaceFavorites(defaults: defaults).contains("maritime-museum"))
        XCTAssertTrue(favorites.contains("my-custom-place"))
        XCTAssertTrue(PlaceFavorites(defaults: other).ids.isEmpty)
        favorites.toggle("maritime-museum")
        XCTAssertFalse(PlaceFavorites(defaults: defaults).contains("maritime-museum"))
        XCTAssertTrue(favorites.contains("my-custom-place"))
    }
}
