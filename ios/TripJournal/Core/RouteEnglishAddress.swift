import Foundation

struct RouteEnglishAddress: Codable, Equatable, Sendable {
    var name: String
    var address: String

    // Preserve postal/unit/branch information; remove only identical comma components.
    var copyText: String? {
        let destination = TripConfig.current.destination, suffix = Self.clean(destination.addressSuffix)
        let address = Self.withoutDestinationPrefix(address)
        guard Self.isEnglish(name), Self.isEnglish(address), name.count <= 500, address.count <= 1000 else { return nil }
        let name = Self.clean(name), place = NSRegularExpression.escapedPattern(for: suffix)
        let postcode = destination.postcodePattern.flatMap { $0.isEmpty ? nil : "(?:\($0))" }
        let tail = postcode.map { "(?:\\s+\($0))?" } ?? ""
        var parts = [name]
        var postal: String?
        func takePostal(_ text: String) {
            if let postcode, let range = text.range(of: postcode + "$", options: .regularExpression) { postal = String(text[range]) }
        }
        for raw in address.components(separatedBy: ",") {
            var part = Self.clean(raw)
            if part.isEmpty { continue }
            if !suffix.isEmpty {
                if part.range(of: "^\(place)\(tail)$", options: [.regularExpression, .caseInsensitive]) != nil { takePostal(part); continue }
                if let postcode, part.range(of: "^\(postcode)$", options: .regularExpression) != nil { postal = part; continue }
                if let range = part.range(of: "\\s+\(place)\(tail)$", options: [.regularExpression, .caseInsensitive]) {
                    takePostal(String(part[range]))
                    part = String(part[..<range.lowerBound])
                }
            }
            if !parts.contains(where: { $0.caseInsensitiveCompare(part) == .orderedSame }) { parts.append(part) }
        }
        // A destination name alone is not an address. Named landmarks are valid address components.
        let noise = suffix.isEmpty ? ["[,\\s]"] : ["\\b\(place)\\b"] + (postcode.map { ["\\b\($0)\\b"] } ?? []) + ["[,\\s]"]
        guard !address.replacingOccurrences(of: "(?i)" + noise.joined(separator: "|"), with: "", options: .regularExpression).isEmpty else { return nil }
        if !suffix.isEmpty { parts.append(suffix + (postal.map { " " + $0 } ?? "")) }
        return parts.joined(separator: ", ")
    }
    // Map apps often prefix a local-language destination name ("<城市名>1 Some Road"); drop it.
    static func withoutDestinationPrefix(_ text: String) -> String {
        let name = TripConfig.current.destination.name, value = clean(text)
        return !name.isEmpty && value.hasPrefix(name) ? clean(String(value.dropFirst(name.count))) : value
    }
    static func clean(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    static func isEnglish(_ text: String) -> Bool {
        let value = clean(text)
        return value.range(of: "[A-Za-z]", options: .regularExpression) != nil
            && value.range(of: #"[\p{L}&&[^\p{Latin}]]"#, options: .regularExpression) == nil
            && !value.contains("://")
    }
}

extension RouteNode {
    // Location contents bind a correction to the exact destination that was confirmed.
    var englishAddressKey: String {
        "address:" + RoutePreferences.digest([locationKey, location?.name ?? "", location?.address ?? "",
                                              location.map { String($0.latitude) } ?? "", location.map { String($0.longitude) } ?? ""])
    }
    func englishAddress(in preferences: RoutePreferences) -> RouteEnglishAddress? {
        preferences.values[englishAddressKey]?.englishAddress ?? defaultEnglishAddress
    }
}
