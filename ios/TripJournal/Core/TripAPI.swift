import Foundation
import Security

struct RemoteSnapshot: Codable, Sendable {
    var revision: Int
    var state: TripPlan
    var updatedAt: Double
    enum CodingKeys: String, CodingKey { case revision, state, updatedAt }
    init(revision: Int, state: TripPlan, updatedAt: Double) { self.revision = revision; self.state = state; self.updatedAt = updatedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revision = try c.decode(Int.self, forKey: .revision)
        updatedAt = try c.decode(Double.self, forKey: .updatedAt)
        state = try PlanCompatibility.decode(c.decode(JSONValue.self, forKey: .state))
    }
}
enum PlanCompatibility {
    static func decode(_ raw: JSONValue) throws -> TripPlan {
        let plan = try raw.decode(TripPlan.self)
        guard try JSONValue.wrap(plan) == raw else { throw TripError.message("共享行程包含此版本尚不支持的数据。请更新 App；本机草稿已保留，未覆盖共享内容。") }
        return plan
    }
}
struct SessionCredentials: Codable, Sendable { var cookie: String; var csrf: String; var expiresAt: Double }
enum APIError: Error { case unauthorized; case conflict(RemoteSnapshot); case response(Int, String) }

enum CredentialVault {
    private static var service: String { AppIdentity.appBundleID + ".shared-session" }
    static func read() throws -> SessionCredentials? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw TripError.message("无法读取安全登录信息（\(status)）") }
        return try JSONDecoder().decode(SessionCredentials.self, from: data)
    }
    static func write(_ value: SessionCredentials?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        guard let value else { let status = SecItemDelete(query as CFDictionary); if status != errSecSuccess && status != errSecItemNotFound { throw TripError.message("无法退出登录") }; return }
        let bytes = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw TripError.message("无法安全保存登录信息（\(status)）") }; return
        }
        guard updated == errSecSuccess else { throw TripError.message("无法更新登录信息（\(updated)）") }
    }
}
protocol TripService: Sendable {
    // False when no backend is configured: the app then runs entirely on this device.
    var isConfigured: Bool { get }
    func connect() async throws -> SessionCredentials
    func snapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RemoteSnapshot?
    func save(_ plan: TripPlan, revision: Int, credentials: SessionCredentials) async throws -> Int
    func attachment(_ file: TicketFile, credentials: SessionCredentials, cellular: Bool) async throws -> Data
    func upload(_ data: Data, type: String, credentials: SessionCredentials) async throws -> TicketFile
}
extension TripService { var isConfigured: Bool { true } }
actor TripAPI: TripService, RoutePreferenceTransport {
    // The optional self-hosted backend (Info.plist TripServerURL). nil means offline mode.
    static var baseURL: URL? {
        #if DEBUG
        if let local = integrationURL { return local }
        #endif
        return AppIdentity.serverURL
    }
    static var isConfigured: Bool { baseURL != nil }
    #if DEBUG
    static var integrationURL: URL? {
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"], let local = URL(string: raw), ["127.0.0.1", "localhost"].contains(local.host ?? "") else { return nil }
        return local
    }
    #endif
    private let session: URLSession
    private let endpoint: URL?
    private let accessKey: String
    private var routeCredentials: SessionCredentials?
    nonisolated var isConfigured: Bool { endpoint != nil }
    init(endpoint: URL? = TripAPI.baseURL, accessKey: String? = nil) {
        #if DEBUG
        if let local = Self.integrationURL {
            self.endpoint = local
            self.accessKey = String(repeating: "t", count: 48)
        } else {
            self.endpoint = endpoint
            self.accessKey = accessKey ?? (Bundle.main.object(forInfoDictionaryKey: "TripSharedAccessKey") as? String ?? "")
        }
        #else
        self.endpoint = endpoint
        self.accessKey = accessKey ?? (Bundle.main.object(forInfoDictionaryKey: "TripSharedAccessKey") as? String ?? "")
        #endif
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false; c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 20
        session = URLSession(configuration: c)
    }
    private func request(_ path: String, method: String = "GET", credentials: SessionCredentials? = nil, body: Data? = nil, type: String = "application/json", cellular: Bool = true, query: [URLQueryItem] = [], touchDevice: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let endpoint else { throw TripError.message(Self.offlineMessage) }
        var components = URLComponents(url: endpoint.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var r = URLRequest(url: components.url!)
        r.httpMethod = method; r.httpBody = body; r.allowsCellularAccess = cellular
        var origin = URLComponents(); origin.scheme = endpoint.scheme; origin.host = endpoint.host; origin.port = endpoint.port
        r.setValue(origin.string, forHTTPHeaderField: "Origin")
        r.setValue(type, forHTTPHeaderField: "Content-Type")
        if let touchDevice { r.setValue(touchDevice, forHTTPHeaderField: "X-Touch-Device") }
        if let credentials {
            r.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
            r.setValue(credentials.csrf, forHTTPHeaderField: "X-Trip-CSRF")
        }
        let (data, response) = try await session.data(for: r)
        guard let h = response as? HTTPURLResponse else { throw TripError.message("服务器响应无效") }
        if h.statusCode == 401 { throw APIError.unauthorized }
        if h.statusCode == 409, path == "api/route-preferences" {
            struct Conflict: Decodable { var latest: RoutePreferenceSnapshot }
            throw RoutePreferenceError.conflict(try JSONDecoder().decode(Conflict.self, from: data).latest)
        }
        if h.statusCode == 409 {
            // Only a plan save answers with a snapshot; other 409s (a taken interaction slot)
            // must keep their own message instead of failing to decode as a conflict.
            struct Conflict: Decodable { var latest: RemoteSnapshot }
            if let conflict = try? JSONDecoder().decode(Conflict.self, from: data) { throw APIError.conflict(conflict.latest) }
        }
        guard (200..<300).contains(h.statusCode) else {
            struct Failure: Decodable { var error: String }
            throw APIError.response(h.statusCode, (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "服务器暂时不可用")
        }
        return (data, h)
    }
    static let offlineMessage = "未配置共享后端，此功能需要自建后端（见 docs/zh/backend.md）。"
    func touch(_ action: String, body: Data?, secret: String, credentials: SessionCredentials, query: [URLQueryItem] = []) async throws -> Data {
        try await request("api/touch/" + action, method: body == nil ? "GET" : "POST", credentials: credentials,
                          body: body, query: query, touchDevice: secret).0
    }
    func connect() async throws -> SessionCredentials {
        guard endpoint != nil else { throw TripError.message(Self.offlineMessage) }
        guard accessKey.count >= 32, !accessKey.contains("$(") else { throw TripError.message("此版本缺少自动共享配置，请更新 App。") }
        return try await openSession("api/native-session", body: ["accessKey": accessKey])
    }
    private func openSession(_ path: String, body: [String: String]) async throws -> SessionCredentials {
        let (_, h) = try await request(path, method: "POST", body: JSONEncoder().encode(body))
        guard let field = h.value(forHTTPHeaderField: "Set-Cookie"), let cookie = field.split(separator: ";").first, cookie.hasPrefix("trip_session=") else { throw TripError.message("服务器未返回登录凭证") }
        var credentials = SessionCredentials(cookie: String(cookie), csrf: "", expiresAt: 0)
        struct Bootstrap: Decodable { var csrf: String; var expiresAt: Double }
        let (data, _) = try await request("api/session", credentials: credentials)
        let info = try JSONDecoder().decode(Bootstrap.self, from: data)
        credentials.csrf = info.csrf; credentials.expiresAt = info.expiresAt
        return credentials
    }
    func snapshot(_ credentials: SessionCredentials, since: Int? = nil) async throws -> RemoteSnapshot? {
        let query = since.map { [URLQueryItem(name: "since", value: String($0))] } ?? []
        let (data, response) = try await request("api/plan", credentials: credentials, query: query)
        if response.statusCode == 204 { return nil }
        return try JSONDecoder().decode(RemoteSnapshot.self, from: data)
    }
    func save(_ plan: TripPlan, revision: Int, credentials: SessionCredentials) async throws -> Int {
        struct Payload: Encodable { var revision: Int; var state: TripPlan; var device = "ios" }
        struct Saved: Decodable { var revision: Int }
        let (data, _) = try await request("api/plan", method: "PUT", credentials: credentials, body: JSONEncoder().encode(Payload(revision: revision, state: plan)))
        return try JSONDecoder().decode(Saved.self, from: data).revision
    }
    func searchRoutePlaces(_ query: String) async throws -> [RouteLocation] {
        if (routeCredentials?.expiresAt ?? 0) <= Date().timeIntervalSince1970 + 60 { routeCredentials = try await connect() }
        do {
            let (data, _) = try await request("api/route-places", credentials: routeCredentials, query: [.init(name: "query", value: query)])
            struct Response: Decodable { var places: [RouteLocation] }
            return try JSONDecoder().decode(Response.self, from: data).places.filter(\.valid)
        } catch APIError.unauthorized { routeCredentials = nil; throw APIError.unauthorized }
    }
    func calculateRoute(from: [Double], to: [Double], driving: Bool) async throws -> RoadRouteResponse {
        struct Payload: Encodable { var from: [Double]; var to: [Double]; var mode: String }
        let payload = try JSONEncoder().encode(Payload(from: from, to: to, mode: driving ? "driving" : "walking"))
        for attempt in 0..<2 {
            if (routeCredentials?.expiresAt ?? 0) <= Date().timeIntervalSince1970 + 60 { routeCredentials = try await connect() }
            do {
                let (data, _) = try await request("api/routes", method: "POST", credentials: routeCredentials, body: payload)
                return try JSONDecoder().decode(RoadRouteResponse.self, from: data)
            } catch APIError.unauthorized {
                routeCredentials = nil
                if attempt == 1 { throw APIError.unauthorized }
            }
        }
        throw APIError.unauthorized
    }
    func englishAddressSharing(_ credentials: SessionCredentials) async throws -> Bool {
        let (data, _) = try await request("api/route-address-status", credentials: credentials)
        struct Status: Decodable { var enabled: Bool }
        return try JSONDecoder().decode(Status.self, from: data).enabled
    }
    func routeSnapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RoutePreferenceSnapshot? {
        let query = since.map { [URLQueryItem(name: "since", value: String($0))] } ?? []
        let (data, response) = try await request("api/route-preferences", credentials: credentials, query: query)
        if response.statusCode == 204 { return nil }
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)
        let snapshot = try raw.decode(RoutePreferenceSnapshot.self)
        guard try JSONValue.wrap(snapshot) == raw else { throw TripError.message("路线设置包含尚不支持的数据，请更新 App") }
        return snapshot
    }
    func saveRoutes(_ state: RoutePreferences, revision: Int, credentials: SessionCredentials) async throws -> Int {
        struct Payload: Encodable { var revision: Int; var state: RoutePreferences }
        struct Saved: Decodable { var revision: Int }
        let (data, _) = try await request("api/route-preferences", method: "PUT", credentials: credentials, body: JSONEncoder().encode(Payload(revision: revision, state: state)))
        return try JSONDecoder().decode(Saved.self, from: data).revision
    }
    func attachment(_ file: TicketFile, credentials: SessionCredentials, cellular: Bool) async throws -> Data {
        try await request("api/attachments/" + file.id, credentials: credentials, cellular: cellular).0
    }
    func upload(_ data: Data, type: String, credentials: SessionCredentials) async throws -> TicketFile {
        let (body, _) = try await request("api/attachments", method: "POST", credentials: credentials, body: data, type: type)
        struct FileResponse: Decodable { var id: String; var type: String; var size: Int }
        let response = try JSONDecoder().decode(FileResponse.self, from: body)
        return TicketFile(id: response.id, name: "附件", type: response.type, size: response.size)
    }
}
