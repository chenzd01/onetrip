import Foundation

struct Place: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var en: String
    var zone: String
    var kind: String
    var hours: Double
    var budget: Double
    var desc: String
    var tip: String
    var travel: String
    var rain: String
    var food: String
    var link: String
    var opening: String?
    var price: String?
    var bestTime: String?
    var isDining: Bool { kind == "餐饮" }
    var guides: [DestinationGuide]?
}
struct DestinationGuide: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var summary: String
    var updatedAt: String
    var sections: [Section]
    var links: [SourceLink]
    struct Section: Codable, Hashable, Sendable {
        var title: String
        var paragraphs: [String]
    }
}
struct Stop: Codable, Identifiable, Equatable, Sendable {
    var uid: String
    var place: String
    var time: String
    var note: String
    var durationMinutes: Int?
    var meal: MealPlan?
    var id: String { uid }

    func duration(fallbackHours: Double) -> Int {
        durationMinutes ?? Int((fallbackHours * 60).rounded())
    }
    static func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60, remainder = minutes % 60
        if hours == 0 { return "\(remainder) 分钟" }
        return remainder == 0 ? "\(hours) 小时" : "\(hours) 小时 \(remainder) 分钟"
    }
    func scheduleLabel(fallbackHours: Double) -> String {
        let minutes = duration(fallbackHours: fallbackHours)
        let length = Self.durationLabel(minutes)
        if time.isEmpty { return "时间待定 · 建议 \(length)" }
        let components = time.split(separator: ":").compactMap { Int($0) }
        let overnight = components.count == 2 && components[0] * 60 + components[1] + minutes >= 1440
        return "\(time) + \(durationMinutes == nil ? "约 " : "")\(length)\(overnight ? " · 次日结束" : "")"
    }
}
struct TripDay: Codable, Identifiable, Equatable, Sendable {
    var date: String
    var title: String
    var area: String
    var note: String
    var items: [Stop]
    var id: String { date }
    var chronologicalItems: [Stop] {
        items.enumerated().sorted {
            let left = $0.element.time.isEmpty ? "24:00" : $0.element.time
            let right = $1.element.time.isEmpty ? "24:00" : $1.element.time
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
}
// Trip totals for the whole party: flights in the home currency, everything else in the local currency.
struct Budget: Codable, Equatable, Sendable {
    var flightOut: Double
    var flightReturn: Double
    var hotel: Double
    var food: Double
    var transport: Double
    var other: Double
}
struct Stay: Codable, Identifiable, Equatable, Sendable {
    var nameEnglish: String?
    var id = UUID().uuidString.lowercased()
    var name = ""
    var address = ""
    var phone = ""
    var checkIn = TripConfig.current.stayRange.first
    var checkOut = TripConfig.current.stayRange.last
    var checkInTime = "15:00"
    var checkOutTime = "12:00"
    var lateArrival = false
    var notes = ""
}
struct TicketFile: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var type: String
    var size: Int
}
struct Ticket: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString.lowercased()
    var title = ""
    var status = "planned"
    var quantity = TripConfig.current.partySize
    var date = ""
    var time = ""
    var provider = ""
    var reference = ""
    var url = ""
    var deadline = ""
    var notes = ""
    var files: [TicketFile] = []
}
struct TripPlan: Codable, Equatable, Sendable {
    var version: Int
    var id: String
    var days: [TripDay]
    var custom: [Place]
    var checks: [String: Bool]
    var budget: Budget
    var hotelFavorites: [String]?
    var stays: [Stay]?
    var tickets: [String: [Ticket]]?
}
struct Preparation: Codable, Identifiable, Sendable {
    var guideImage: String?
    var id: String
    var group: String
    var title: String
    var summary: String
    var body: [String]
    var copy: String?
    var links: [SourceLink]
    var dueDate: String?

    func isDue(on day: String) -> Bool { dueDate.map { day >= $0 } ?? true }
}
struct Photo: Codable, Identifiable, Hashable, Sendable {
    var path: String
    var caption: String
    var sourceUrl: String
    var creator: String
    var license: String
    var licenseUrl: String
    var width: Int
    var height: Int
    var id: String { path }
}
struct Album: Codable, Sendable { var thumb: String; var photos: [Photo] }
struct PostImage: Codable, Hashable, Sendable {
    var path: String
    var order: Int
    var width: Int
    var height: Int
}
struct Post: Codable, Identifiable, Sendable {
    var id: String
    var platform: String
    var title: String
    var body: String?
    var author: String
    var date: String
    var heat: String
    var url: String
    var summary: String?
    var capturedAt: String
    var categories: [String]
    var images: [PostImage]
    var thumb: String
    var guidePlaces: [String]?
    var platformName: String { ["xiaohongshu": "小红书", "web": "网页"][platform] ?? platform }
}
struct Hotel: Codable, Identifiable, Sendable {
    struct Picture: Codable, Sendable { var path: String; var source: String }
    struct Room: Codable, Sendable {
        struct Quote: Codable, Sendable {
            var status: String
            var totalHome: Double?
            var breakfast: String?
            var cancel: String?
            var confirmation: String?
            var extraFees: String?
        }
        var name: String
        var area: String?
        var bed: String
        var view: String?
        var quote: Quote
    }
    var id: String
    var name: String
    var en: String
    var region: String
    var reason: String
    var notice: String
    var address: String
    var coords: [Double]
    var source: String
    var checkedAt: String
    var policies: [String]
    var transport: [String]
    var rooms: [Room]
    var photo: Picture
    var thumb: String
    var tier: String?
}
struct ReferenceGuide: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var body: String
    var links: [SourceLink]
}
struct Flight: Codable, Identifiable, Sendable {
    var id: String
    var number: String
    var from: String
    var to: String
    var departure: String
    var arrival: String
}
struct ContentCatalog: Codable, Sendable {
    struct PlaceLocation: Codable, Sendable { var name: String; var address: String; var coordinates: [Double]; var source: String }
    struct Catalog: Codable, Sendable { var places: [Place]; var days: [TripDay] }
    struct Hotels: Codable, Sendable { var hotels: [Hotel] }
    var trip: TripConfig
    var catalog: Catalog
    var defaults: TripPlan
    var preparation: [Preparation]
    var hotels: Hotels
    var photos: [String: Album]
    var posts: [Post]
    var references: [ReferenceGuide]
    var flights: [Flight]
    var locations: [String: PlaceLocation]
    var phrases: [PhraseSection]
    var dining: DiningCatalog?
    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Content") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    static func resource(_ path: String) -> URL? {
        Bundle.main.resourceURL?.appending(path: "Content").appending(path: path)
    }
}
