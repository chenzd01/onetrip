import Foundation
import Security

enum TouchKind: String, Codable, Sendable, CaseIterable {
    case poke, heart
    var title: String { self == .poke ? "弹一弹" : "送爱心" }
    var symbol: String { self == .poke ? "hand.tap" : "heart.fill" }
    var acknowledgement: String { self == .poke ? "弹出去了" : "爱心送出啦" }
}
struct TouchProfile: Codable, Sendable, Equatable {
    var memberID: String
    var nickname: String
    var partnerName: String?
    var partnerID: String?
    var candidateName: String?
    var inviteExpires: Double?
    var waiting: Bool
}
struct TouchEvent: Codable, Identifiable, Sendable, Equatable {
    var seq: Int
    var id: String
    var sender: String
    var recipient: String
    var kind: TouchKind
    var name: String
    var created: Double
    var message: String { kind == .heart ? "给你比心" : "弹了弹你" }
}
struct TouchFeed: Codable, Sendable { var events: [TouchEvent]; var cursor: Int; var hasMore: Bool }
/// APNs acceptance confirms submission to Apple, not presentation or sound on the device.
struct TouchReceipt: Codable, Sendable {
    var event: TouchEvent?
    var alert: String?
    var notificationState: String?
    func acknowledgement(for kind: TouchKind) -> String {
        let sent = kind.acknowledgement
        switch notificationState {
        case "pending", "sending": return sent + "，正在发送系统通知"
        case "accepted": return sent + "，已提交系统通知"
        case "failed", "expired", "cancelled": return sent + "，系统通知未能发出，对方打开 App 后可看到"
        case "uncertain": return sent + "，系统通知状态暂未确认"
        case "not-queued": return sent + "，这次未安排系统通知"
        case "no-token": return sent + "，对方的通知连接未就绪，打开 App 后可看到"
        default: return alert == "silent" ? sent + "，对方打开 App 后可看到" : sent
        }
    }
}
struct TouchInvite: Codable, Sendable { var code: String; var expires: Double }
struct TouchCommand: Codable, Sendable, Equatable { var id: String; var kind: TouchKind }
struct TouchArchive: Codable {
    var profile: TouchProfile?
    var events: [TouchEvent] = []
    var cursor = 0
    var noticed: Set<String> = []
    var played: Set<String> = []
    var systemNotified: [String: Double]?
    var pending: TouchCommand?
    var invite: TouchInvite?
    var welcomeDismissed: Bool?
    mutating func prune(now: Date) {
        events.removeAll { $0.created < now.timeIntervalSince1970 - 7 * 86400 }
        let ids = Set(events.map(\.id))
        noticed.formIntersection(ids); played.formIntersection(ids)
        systemNotified = systemNotified?.filter { $0.value >= now.timeIntervalSince1970 - 7 * 86400 }
        if let invite, invite.expires <= now.timeIntervalSince1970 { self.invite = nil }
    }
}

enum TouchVault {
    private static var service: String { AppIdentity.appBundleID + ".touch-device" }
    static func secret(reset: Bool = false) throws -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if reset {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw TripError.message("无法重置互动设备凭证") }
        }
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { _, new in new } as CFDictionary, &value)
        if status == errSecSuccess, let bytes = value as? Data, let secret = String(data: bytes, encoding: .utf8) { return secret }
        guard status == errSecItemNotFound else { throw TripError.message("暂时无法读取互动设备凭证，请解锁后重试") }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw TripError.message("无法生成互动设备凭证") }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        let attributes = query.merging([kSecValueData as String: Data(secret.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]) { _, new in new }
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw TripError.message("无法保存互动设备凭证") }
        return secret
    }
}

protocol TouchTransport: Sendable {
    func request(_ action: String, body: [String: String]?, after: Int?) async throws -> Data
}
actor TouchAPI: TouchTransport {
    let secret: String
    private let api: TripAPI
    private var credentials: SessionCredentials?
    init(secret: String, api: TripAPI = TripAPI()) { self.secret = secret; self.api = api }
    func request(_ action: String, body: [String: String]? = nil, after: Int? = nil) async throws -> Data {
        #if targetEnvironment(simulator) && !DEBUG
        throw TripError.message("模拟器请使用 Debug 版和本机测试服务")
        #endif
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"],
              let url = URL(string: raw), ["127.0.0.1", "localhost"].contains(url.host ?? "") else {
            throw TripError.message("测试版互动只连接本机测试服务")
        }
        #endif
        var encoded: Data?
        if let body {
            var object: [String: Any] = body
            if body["replace"] == "true" { object["replace"] = true }
            if body["token"] == "" { object["token"] = NSNull() }
            encoded = try JSONSerialization.data(withJSONObject: object)
        }
        if credentials == nil { credentials = try await api.connect() }
        let query = after.map { [URLQueryItem(name: "after", value: String($0))] } ?? []
        guard let credentials else { throw TripError.message("互动连接尚未就绪") }
        do { return try await api.touch(action, body: encoded, secret: secret, credentials: credentials, query: query) }
        catch APIError.unauthorized {
            let renewed = try await api.connect(); self.credentials = renewed
            return try await api.touch(action, body: encoded, secret: secret, credentials: renewed, query: query)
        }
    }
}
