import Foundation
import CryptoKit
import MapKit

struct RouteLocation: Codable, Equatable, Hashable, Sendable {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var valid: Bool { latitude.isFinite && longitude.isFinite && DestinationMaps.contains(coordinate) }
}
struct RouteSetting: Codable, Equatable, Sendable {
    var kind: String
    var title: String
    var value: String?
    var location: RouteLocation?
    var englishAddress: RouteEnglishAddress?
    var readable: String {
        if let englishAddress { return englishAddress.name + "\n" + englishAddress.address }
        if let location { return location.name + "\n" + location.address }
        if kind == "mode" { return value == "driving" ? "打车 · 驾车估算" : "步行" }
        return title
    }
}
struct RoutePreferences: Codable, Equatable, Sendable {
    var tripID: String
    var values: [String: RouteSetting] = [:]
    static func digest(_ parts: [String]) -> String {
        SHA256.hash(data: (try? JSONEncoder().encode(parts)) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
    static func hotelKey(_ date: String, start: Bool) -> String { (start ? "start:" : "end:") + date }
    func validated(for trip: String) throws {
        guard tripID == trip, values.count <= 2000 else { throw TripError.message("路线设置不属于这次旅行") }
        for (key, setting) in values {
            guard !key.isEmpty, key.count <= 500, !setting.title.isEmpty, setting.title.count <= 500 else { throw TripError.message("路线设置无效") }
            guard setting.kind == "englishAddress" || setting.englishAddress == nil else { throw TripError.message("英文地址记录无效") }
            switch setting.kind {
            case "englishAddress":
                guard key.hasPrefix("address:"), setting.englishAddress?.copyText != nil, setting.location == nil, setting.value == nil else { throw TripError.message("请填写英文地点名和地址") }
            case "location":
                guard let location = setting.location, location.valid, !location.name.isEmpty, location.name.count <= 500,
                      location.address.count <= 1000, setting.value == nil else { throw TripError.message("请选择\(TripConfig.current.destination.name)范围内的位置") }
            case "mode":
                guard ["walking", "driving"].contains(setting.value), setting.location == nil else { throw TripError.message("交通方式无效") }
            case "startHotel", "endHotel":
                guard let value = setting.value, !value.isEmpty, value.count <= 120, setting.location == nil else { throw TripError.message("酒店设置无效") }
            default: throw TripError.message("路线设置需要更新 App 才能读取；本机草稿已保留")
            }
        }
    }
}
struct RoutePreferenceConflict: Identifiable {
    var id: String
    var local: RouteSetting?
    var remote: RouteSetting?
    var title: String { local?.title ?? remote?.title ?? "路线设置" }
}
enum RoutePreferenceMerge {
    static func merge(base: RoutePreferences, local: RoutePreferences, remote: RoutePreferences, choices: [String: MergeChoice] = [:]) -> (RoutePreferences, [RoutePreferenceConflict]) {
        var result = remote
        var conflicts: [RoutePreferenceConflict] = []
        for key in Set(base.values.keys).union(local.values.keys).union(remote.values.keys) {
            let b = base.values[key], l = local.values[key], r = remote.values[key]
            if l == r || r == b { result.values[key] = l }
            else if l == b { result.values[key] = r }
            else if let choice = choices[key] { result.values[key] = choice == .local ? l : r }
            else { conflicts.append(.init(id: key, local: l, remote: r)) }
        }
        return (result, conflicts.sorted { $0.id < $1.id })
    }
}
struct RouteNode: Identifiable, Equatable {
    var id: String
    var locationKey: String
    var name: String
    var query: String
    var time: String
    var stopID: String?
    var location: RouteLocation?
    var defaultEnglishAddress: RouteEnglishAddress?
}
// A repeated stop keeps its itinerary identity even when it shares a map coordinate.
struct RouteMapGroup: Identifiable {
    struct Stop: Identifiable {
        var number: Int
        var node: RouteNode
        var id: String { node.id }
    }
    var location: RouteLocation
    var stops: [Stop]
    var id: String { String(location.latitude) + ":" + String(location.longitude) }
    var label: String { stops.map { String($0.number) }.joined(separator: "·") }

    static func groups(for nodes: [RouteNode]) -> [RouteMapGroup] {
        var groups: [RouteMapGroup] = []
        for (index, node) in nodes.enumerated() {
            guard let location = node.location, location.valid else { continue }
            let stop = Stop(number: index + 1, node: node)
            if let match = groups.firstIndex(where: { $0.location.latitude == location.latitude && $0.location.longitude == location.longitude }) {
                groups[match].stops.append(stop)
            } else {
                groups.append(RouteMapGroup(location: location, stops: [stop]))
            }
        }
        return groups
    }
}
struct RouteLeg: Identifiable, Equatable {
    var id: String
    var from: RouteNode
    var to: RouteNode
    var driving: Bool
    var title: String { from.name + " → " + to.name }
    var requestKey: String? {
        guard let a = from.location, let b = to.location, a.valid, b.valid else { return nil }
        return RoutePreferences.digest([String(a.latitude), String(a.longitude), String(b.latitude), String(b.longitude), driving ? "driving" : "walking"])
    }
}
struct DayRoute {
    var nodes: [RouteNode]
    var flexible: [Stop]
    var legs: [RouteLeg]
    var warnings: [String]
    init(day: TripDay, plan: TripPlan, content: ContentCatalog, preferences: RoutePreferences) {
        var points: [RouteNode] = []
        var notices: [String] = []
        let places = content.catalog.places + plan.custom
        func hotel(start: Bool) -> RouteNode? {
            guard let id = preferences.values[RoutePreferences.hotelKey(day.date, start: start)]?.value else { return nil }
            guard let stay = plan.stays?.first(where: { $0.id == id }) else {
                notices.append((start ? "出发" : "返回") + "酒店已不在住宿记录中，请重新选择")
                return nil
            }
            let key = "hotel:" + RoutePreferences.digest([id, stay.nameEnglish ?? stay.name, stay.address])
            let known = content.hotels.hotels.first { !$0.address.isEmpty && $0.address == stay.address }
            let coordinates = known?.coords
            var location = preferences.values[key]?.location
            if location == nil, let coordinates, coordinates.count == 2 {
                location = RouteLocation(name: stay.name, address: stay.address, latitude: coordinates[0], longitude: coordinates[1])
            }
            return RouteNode(id: (start ? "start:" : "end:") + key, locationKey: key, name: stay.name,
                             query: StayMaps.destination(stay), time: start ? "出发酒店" : "返回酒店", location: location?.valid == true ? location : nil,
                             defaultEnglishAddress: preferences.values[key]?.location.map { RouteEnglishAddress(name: $0.name, address: $0.address) }
                                ?? RouteEnglishAddress(name: stay.nameEnglish?.isEmpty == false ? stay.nameEnglish! : (known?.en ?? ""), address: stay.address))
        }
        if let start = hotel(start: true) { points.append(start) }
        for stop in day.chronologicalItems where !stop.time.isEmpty {
            let place = places.first { $0.id == stop.place }
            let key = "place:" + stop.place
            var location = preferences.values[key]?.location
            if location == nil, let known = content.locations[stop.place], known.coordinates.count == 2 {
                location = RouteLocation(name: known.name, address: known.address, latitude: known.coordinates[0], longitude: known.coordinates[1])
            }
            if location == nil, let venue = content.dining?.restaurants.first(where: { $0.id == stop.place }), let coords = venue.coordinates {
                location = RouteLocation(name: venue.name, address: venue.address, latitude: coords.latitude, longitude: coords.longitude)
            }
            points.append(RouteNode(id: "stop:" + RoutePreferences.digest([stop.uid, stop.place]), locationKey: key,
                                    name: place?.name ?? "地点已不可用", query: place?.en.isEmpty == false ? place!.en : (place?.name ?? ""),
                                    time: stop.time, stopID: stop.uid, location: location?.valid == true ? location : nil,
                                    defaultEnglishAddress: preferences.values[key]?.location.map { RouteEnglishAddress(name: $0.name, address: $0.address) }
                                        ?? content.locations[stop.place].map { RouteEnglishAddress(name: place?.en.isEmpty == false ? place!.en : $0.name, address: $0.address) }
                                        ?? content.dining?.restaurants.first(where: { $0.id == stop.place }).map { RouteEnglishAddress(name: $0.en, address: $0.address) }))
        }
        if let end = hotel(start: false) { points.append(end) }
        nodes = points; flexible = day.items.filter { $0.time.isEmpty }; warnings = notices
        legs = zip(points, points.dropFirst()).map { a, b in
            let key = "mode:" + day.date + ":" + RoutePreferences.digest([a.id, b.id])
            return RouteLeg(id: key, from: a, to: b, driving: preferences.values[key]?.value == "driving")
        }
    }
}
