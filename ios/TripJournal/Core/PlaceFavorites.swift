import Foundation
import Observation

@MainActor @Observable final class PlaceFavorites {
    static let shared = PlaceFavorites()
    private(set) var ids: Set<String>
    private let defaults: UserDefaults
    private static let key = "place-favorites"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        defaults.set(ids.sorted(), forKey: Self.key)
    }
}
