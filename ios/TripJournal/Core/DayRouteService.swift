import Foundation
import MapKit
import Observation

struct RouteResult {
    var polyline: MKPolyline
    var distance: Double
    var seconds: Double
    var calculatedAt: Date
}
@MainActor protocol RouteCalculating {
    func calculate(_ leg: RouteLeg) async throws -> RouteResult
}
struct RoadRouteResponse: Decodable, Sendable {
    var shape: String
    var precision: Int
    var distance: Double
    var seconds: Double
    var calculatedAt: Double
    var source: String

    func coordinates() throws -> [CLLocationCoordinate2D] {
        guard precision == 6, distance.isFinite, distance >= 0, seconds.isFinite, seconds >= 0,
              calculatedAt.isFinite, (2...200_000).contains(shape.utf8.count) else {
            throw TripError.message("路线结果无效，请重试")
        }
        let bytes = Array(shape.utf8)
        var index = 0, latitude = 0, longitude = 0
        var result: [CLLocationCoordinate2D] = []
        func delta() throws -> Int {
            var value = 0, shift = 0
            while index < bytes.count, shift <= 30 {
                let raw = Int(bytes[index]); index += 1
                guard (63...126).contains(raw) else { break }
                let byte = raw - 63
                value |= (byte & 31) << shift
                if byte < 32 { return value & 1 == 0 ? value >> 1 : ~(value >> 1) }
                shift += 5
            }
            throw TripError.message("路线坐标不完整，请重试")
        }
        // Road shapes may leave the trip bounds slightly (ring roads, bridges); reject anything far outside.
        let area = TripConfig.current.map.bounds, pad = 0.5
        while index < bytes.count {
            latitude += try delta(); longitude += try delta()
            let coordinate = CLLocationCoordinate2D(latitude: Double(latitude) / 1_000_000, longitude: Double(longitude) / 1_000_000)
            guard CLLocationCoordinate2DIsValid(coordinate), (area.minLat - pad...area.maxLat + pad).contains(coordinate.latitude),
                  (area.minLon - pad...area.maxLon + pad).contains(coordinate.longitude) else {
                throw TripError.message("路线超出支持区域")
            }
            result.append(coordinate)
        }
        guard result.count >= 2 else { throw TripError.message("路线缺少道路坐标") }
        return result
    }
}
@MainActor final class ServerRouteCalculator: RouteCalculating {
    private let api: TripAPI
    init(api: TripAPI = TripAPI()) { self.api = api }
    func calculate(_ leg: RouteLeg) async throws -> RouteResult {
        guard let a = leg.from.location, let b = leg.to.location else { throw TripError.message("请先确认地图位置") }
        if a.latitude == b.latitude && a.longitude == b.longitude {
            return RouteResult(polyline: MKPolyline(coordinates: [a.coordinate], count: 1), distance: 0, seconds: 0, calculatedAt: .now)
        }
        let response = try await api.calculateRoute(from: [a.latitude, a.longitude], to: [b.latitude, b.longitude], driving: leg.driving)
        try Task.checkCancellation()
        let coordinates = try response.coordinates()
        return RouteResult(polyline: MKPolyline(coordinates: coordinates, count: coordinates.count), distance: response.distance,
                           seconds: response.seconds, calculatedAt: Date(timeIntervalSince1970: response.calculatedAt))
    }
}
@MainActor @Observable final class DayRouteService {
    private(set) var results: [String: RouteResult] = [:]
    private(set) var failures: [String: String] = [:]
    private(set) var loading: Set<String> = []
    private var consumers: [UUID: [RouteLeg]] = [:]
    private var jobs: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private var debounce: Task<Void, Never>?
    private var failureDates: [String: Date] = [:]
    private var forced: Set<String> = []
    private var eligibleAt = Date.distantPast
    private var foreground = true
    private let calculator: any RouteCalculating
    init(calculator: any RouteCalculating = ServerRouteCalculator()) { self.calculator = calculator }
    var demand: [String: RouteLeg] {
        var result: [String: RouteLeg] = [:]
        for legs in consumers.values { for leg in legs { if let key = leg.requestKey { result[key] = leg } } }
        return result
    }
    func observe(_ legs: [RouteLeg], consumer: UUID) {
        let previous = consumers[consumer]?.map(\.requestKey)
        consumers[consumer] = legs
        guard previous != legs.map(\.requestKey) else { return }
        schedule()
    }
    func release(_ consumer: UUID) { consumers[consumer] = nil; schedule() }
    func refresh(_ legs: [RouteLeg]) {
        for key in legs.compactMap(\.requestKey) { forced.insert(key); failures[key] = nil; failureDates[key] = nil }
        schedule()
    }
    func tick() { pump() }
    func setForeground(_ active: Bool) {
        foreground = active
        if active { schedule() }
        else { debounce?.cancel(); for job in jobs.values { job.cancel() } }
    }
    private func schedule() {
        let wanted = demand
        for (key, job) in jobs where wanted[key] == nil { job.cancel() }
        debounce?.cancel()
        eligibleAt = Date().addingTimeInterval(0.5)
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.pump()
        }
    }
    private func pump() {
        guard foreground, Date() >= eligibleAt else { return }
        let wanted = demand
        // Keep only a bounded number of inactive cached paths in memory.
        if results.count > 500 {
            for key in results.keys.sorted(by: { results[$0]!.calculatedAt < results[$1]!.calculatedAt }) where wanted[key] == nil {
                results[key] = nil
                if results.count <= 400 { break }
            }
        }
        for key in wanted.keys.sorted() {
            guard jobs.count < 2 else { break }
            guard jobs[key] == nil, let leg = wanted[key] else { continue }
            let expired = results[key].map { Date().timeIntervalSince($0.calculatedAt) >= 900 } ?? true
            guard expired || forced.contains(key) else { continue }
            if let failedAt = failureDates[key], Date().timeIntervalSince(failedAt) < 60, !forced.contains(key) { continue }
            forced.remove(key); loading.insert(key)
            let generation = UUID(); generations[key] = generation
            jobs[key] = Task { [weak self] in
                guard let self else { return }
                do {
                    let result = try await self.calculator.calculate(leg)
                    if !Task.isCancelled, self.generations[key] == generation, self.demand[key] != nil {
                        self.results[key] = result; self.failures[key] = nil; self.failureDates[key] = nil
                    }
                } catch {
                    if !Task.isCancelled, self.demand[key] != nil {
                        self.failures[key] = Self.failureMessage(error); self.failureDates[key] = .now
                    }
                }
                self.jobs[key] = nil; self.generations[key] = nil; self.loading.remove(key)
                self.pump()
            }
        }
    }
    func result(for leg: RouteLeg) -> RouteResult? { leg.requestKey.flatMap { results[$0] } }
    func message(for leg: RouteLeg) -> String {
        guard let key = leg.requestKey else { return "请先确认两端地图位置" }
        if loading.contains(key) { return results[key] == nil ? "正在计算路线…" : "正在更新 · 暂用上次结果" }
        if let failure = failures[key] { return results[key] == nil ? failure : "更新失败 · 暂用上次结果" }
        guard let result = results[key] else { return "等待计算路线" }
        if result.distance == 0 { return "同一地图位置" }
        return Self.distance(result.distance) + " · 约 " + Self.duration(result.seconds)
    }
    static func failureMessage(_ error: Error) -> String {
        if case APIError.response(_, let message) = error { return message }
        if case TripError.message(let message) = error { return message }
        return "暂未算出路线，请联网后重试"
    }
    static func distance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) 米" : String(format: "%.1f 公里", meters / 1000)
    }
    static func duration(_ seconds: Double) -> String { Stop.durationLabel(seconds == 0 ? 0 : max(1, Int(ceil(seconds / 60)))) }
}
