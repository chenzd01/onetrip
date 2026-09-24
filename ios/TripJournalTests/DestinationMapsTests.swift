import XCTest
import MapKit
@testable import TripJournal

final class DestinationMapsTests: XCTestCase {
    private let destination = TripConfig.current.destination, map = TripConfig.current.map
    private var inside: CLLocationCoordinate2D { .init(latitude: map.center[0], longitude: map.center[1]) }
    func testStayMapsEncodeFullDestinationAndPreserveLegacyRecords() throws {
        var stay = Stay()
        stay.name = "测试酒店"
        stay.address = "1 Test Road Suite 203 & Annex"
        stay.phone = "+1 808 555 0100"
        let legacy = try JSONEncoder().encode(stay)
        XCTAssertNil(try JSONDecoder().decode(Stay.self, from: legacy).nameEnglish)
        stay.nameEnglish = "Test & Hotel"
        let roundTrip = try JSONDecoder().decode(Stay.self, from: JSONEncoder().encode(stay))
        XCTAssertEqual(roundTrip.nameEnglish, stay.nameEnglish)
        for google in [false, true] {
            let url = StayMaps.url(stay, google: google)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first { $0.name == (google ? "destination" : "daddr") }?.value, ["Test & Hotel", "1 Test Road Suite 203 & Annex", destination.addressSuffix].filter { !$0.isEmpty }.joined(separator: ", "))
            XCTAssertEqual(url.host, google ? "www.google.com" : "maps.apple.com")
        }
        XCTAssertEqual(StayMaps.destination(stay, coordinates: [inside.latitude, inside.longitude]), "\(inside.latitude),\(inside.longitude)")
        XCTAssertTrue(StayMaps.destination(stay, coordinates: [30, 120]).contains("Test & Hotel"))
        XCTAssertEqual(stay.phoneURL?.absoluteString, "tel:+18085550100")
        XCTAssertTrue(stay.copyText.contains("酒店英文名：Test & Hotel"))
        XCTAssertTrue(stay.copyText.contains("酒店中文名：测试酒店"))
        stay.phone = "待补充"
        XCTAssertNil(stay.phoneURL)
    }

    func testBundledPlaceCoordinatesAreTraceableAndDoNotReplaceCustomPlaces() throws {
        let content = try ContentCatalog.load()
        XCTAssertFalse(content.locations.isEmpty)
        XCTAssertNil(content.locations["custom-test"])
        for (identifier, location) in content.locations {
            XCTAssertTrue(content.catalog.places.contains { $0.id == identifier })
            XCTAssertNotNil(URL(string: location.source))
            XCTAssertNotNil(DestinationMaps.item(name: location.name, address: location.address, coordinates: location.coordinates), identifier)
        }
    }

    func testAllHotelDestinationsRetainExactCatalogCoordinates() throws {
        let hotels = try ContentCatalog.load().hotels.hotels
        try XCTSkipIf(hotels.isEmpty, "content/ has no hotels.json (it is optional)")
        for hotel in hotels {
            let item = try XCTUnwrap(DestinationMaps.item(name: hotel.name, address: hotel.address, coordinates: hotel.coords))
            XCTAssertEqual(item.location.coordinate.latitude, hotel.coords[0], accuracy: 0.000001)
            XCTAssertEqual(item.location.coordinate.longitude, hotel.coords[1], accuracy: 0.000001)
            XCTAssertEqual(item.name, hotel.name)
            XCTAssertEqual(item.address?.fullAddress, hotel.address)
        }
    }

    func testSearchIsScopedToDestinationEvenWhenPhoneIsElsewhere() {
        let request = DestinationMaps.request(for: "Harbor Lighthouse")
        XCTAssertEqual(request.regionPriority, .required)
        XCTAssertTrue(DestinationMaps.contains(request.region.center))
        XCTAssertEqual(request.region.span.latitudeDelta, map.span[0], accuracy: 0.000001)
        XCTAssertEqual(request.naturalLanguageQuery, destination.addressSuffix.isEmpty ? "Harbor Lighthouse" : "Harbor Lighthouse, " + destination.addressSuffix)
        XCTAssertFalse(DestinationMaps.contains(.init(latitude: map.bounds.minLat - 5, longitude: map.bounds.minLon - 5)))
        XCTAssertFalse(DestinationMaps.contains(.init(latitude: map.bounds.maxLat + 0.01, longitude: inside.longitude)))
    }

    func testInvalidOrOutsideCoordinatesNeverBecomeDestinationPins() {
        for coordinates: [Double]? in [nil, [], [inside.latitude], [map.bounds.minLat - 5, map.bounds.minLon - 5], [.nan, inside.longitude], [.infinity, inside.longitude]] {
            XCTAssertNil(DestinationMaps.item(name: "Hotel", address: destination.addressSuffix, coordinates: coordinates))
        }
    }

    func testSearchRejectsNearbyCrossBorderAndUnknownCountryResults() throws {
        try XCTSkipIf(destination.countryCode.isEmpty)
        let nearby = CLLocationCoordinate2D(latitude: map.bounds.maxLat + 0.05, longitude: inside.longitude)
        XCTAssertFalse(DestinationMaps.acceptsSearchResult(coordinate: nearby, regionIdentifier: destination.countryCode))
        XCTAssertFalse(DestinationMaps.acceptsSearchResult(coordinate: inside, regionIdentifier: "ZZ"))
        XCTAssertFalse(DestinationMaps.acceptsSearchResult(coordinate: inside, regionIdentifier: nil))
        XCTAssertTrue(DestinationMaps.acceptsSearchResult(coordinate: inside, regionIdentifier: destination.countryCode))
    }
}
