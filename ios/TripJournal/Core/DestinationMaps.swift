import MapKit

enum DestinationMaps {
    static var region: MKCoordinateRegion {
        let map = TripConfig.current.map
        return MKCoordinateRegion(center: .init(latitude: map.center.first ?? 0, longitude: map.center.last ?? 0),
                                  span: .init(latitudeDelta: map.span.first ?? 1, longitudeDelta: map.span.last ?? 1))
    }

    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        TripConfig.current.map.bounds.contains(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func acceptsSearchResult(coordinate: CLLocationCoordinate2D, regionIdentifier: String?) -> Bool {
        let code = TripConfig.current.destination.countryCode
        return (code.isEmpty || regionIdentifier == code) && contains(coordinate)
    }

    static func request(for query: String) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        let suffix = TripConfig.current.destination.addressSuffix
        request.naturalLanguageQuery = suffix.isEmpty ? query : query + ", " + suffix
        request.region = region
        request.regionPriority = .required
        request.resultTypes = [.pointOfInterest, .address]
        return request
    }

    static func item(name: String, address: String, coordinates: [Double]?) -> MKMapItem? {
        guard let coordinates, coordinates.count == 2 else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: coordinates[0], longitude: coordinates[1])
        guard contains(coordinate) else { return nil }
        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: MKAddress(fullAddress: address, shortAddress: name))
        item.name = name
        return item
    }

    @MainActor static func open(_ item: MKMapItem) -> Bool {
        guard contains(item.location.coordinate) else { return false }
        return item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: item.location.coordinate),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: .init(latitudeDelta: 0.015, longitudeDelta: 0.015))
        ])
    }
}
