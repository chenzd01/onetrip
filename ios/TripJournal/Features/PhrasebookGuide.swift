import Foundation

// Bundled phrasebook from content/phrases.json: independent of bookings, checklist and shared plan state.
struct Phrase: Codable, Identifiable, Hashable, Sendable {
    var id = ""
    var native: String
    var local: String
    var note: String?
    enum CodingKeys: String, CodingKey { case native, local, note }
}

struct PhraseSection: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var items: [Phrase]
    enum CodingKeys: String, CodingKey { case id, title, items }
    init(id: String, title: String, items: [Phrase]) { self.id = id; self.title = title; self.items = items }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        self.id = id
        title = try c.decode(String.self, forKey: .title)
        // Stable per-row identity so playback state survives filtering.
        items = try c.decode([Phrase].self, forKey: .items).enumerated().map { index, phrase in
            var phrase = phrase; phrase.id = "\(id)-\(index)"; return phrase
        }
    }
}
