import Foundation
import Observation

struct RoutePreferenceSnapshot: Codable, Sendable {
    var revision: Int
    var state: RoutePreferences
    var updatedAt: Double
}
enum RoutePreferenceError: Error { case conflict(RoutePreferenceSnapshot) }
protocol RoutePreferenceTransport: Sendable {
    func englishAddressSharing(_ credentials: SessionCredentials) async throws -> Bool
    func connect() async throws -> SessionCredentials
    func routeSnapshot(_ credentials: SessionCredentials, since: Int?) async throws -> RoutePreferenceSnapshot?
    func saveRoutes(_ state: RoutePreferences, revision: Int, credentials: SessionCredentials) async throws -> Int
}
extension RoutePreferenceTransport {
    func englishAddressSharing(_ credentials: SessionCredentials) async throws -> Bool { false }
}
struct SavedRoutePreferences: Codable {
    var state: RoutePreferences
    var base: RoutePreferences
    var revision: Int?
    var pending: Bool
    var englishAddressSharing: Bool?
}
@MainActor @Observable final class RoutePreferenceStore {
    private(set) var state: RoutePreferences
    private(set) var englishAddressSharing = false
    private(set) var pending = false
    private(set) var conflicts: [RoutePreferenceConflict] = []
    private(set) var status = "准备共享路线设置"
    private(set) var busy = false
    var error: String?
    private var base: RoutePreferences
    private var revision: Int?
    private var remoteConflict: RoutePreferenceSnapshot?
    private var credentials: SessionCredentials?
    private var polling: Task<Void, Never>?
    private var foreground = false
    private var failed = false
    private var loadFailed = false
    private let file: URL
    private let api: any RoutePreferenceTransport

    init(tripID: String, directory: URL? = nil, api: any RoutePreferenceTransport = TripAPI()) {
        state = RoutePreferences(tripID: tripID); base = RoutePreferences(tripID: tripID); self.api = api
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "TripWorkspace")
        file = directory.appending(path: "route-preferences.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                let raw = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
                let saved = try raw.decode(SavedRoutePreferences.self)
                guard try JSONValue.wrap(saved) == raw else { throw TripError.message("路线存档需要更新 App 才能读取") }
                try saved.state.validated(for: tripID); try saved.base.validated(for: tripID)
                englishAddressSharing = saved.englishAddressSharing ?? false
                state = saved.state; base = saved.base; revision = saved.revision; pending = saved.pending
                status = pending ? "路线设置已存本机 · 待同步" : "正在检查共享路线设置"
            }
        } catch { loadFailed = true; self.error = "路线存档未被覆盖：" + error.localizedDescription; status = "路线存档暂不可用" }
    }
    private func persist(_ state: RoutePreferences, base: RoutePreferences, revision: Int?, pending: Bool) throws {
        try state.validated(for: self.state.tripID)
        try JSONEncoder().encode(SavedRoutePreferences(state: state, base: base, revision: revision, pending: pending, englishAddressSharing: englishAddressSharing))
            .write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        self.state = state; self.base = base; self.revision = revision; self.pending = pending
    }
    @discardableResult func set(_ key: String, _ value: RouteSetting?) -> Bool {
        guard !loadFailed, conflicts.isEmpty else { error = "请先处理路线设置冲突或存档问题"; return false }
        if value?.kind == "englishAddress", !englishAddressSharing { error = "英文地址共享尚未启用，请等待所有设备更新完成"; return false }
        var next = state; next.values[key] = value
        guard next != state else { return true }
        do {
            try persist(next, base: base, revision: revision, pending: true)
            status = "路线设置已存本机 · 待同步"
            if foreground { Task { await synchronize() } }
            return true
        } catch { self.error = "路线设置未能保存：" + error.localizedDescription; return false }
    }
    func setForeground(_ active: Bool) {
        foreground = active; polling?.cancel(); polling = nil
        guard active else { return }
        polling = Task { [weak self] in
            var delay = 5
            while !Task.isCancelled {
                guard let self else { return }
                await self.synchronize()
                delay = self.failed ? min(delay * 2, 60) : 5
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }
    func synchronize() async {
        guard !busy, !loadFailed, conflicts.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            if (credentials?.expiresAt ?? 0) <= Date().timeIntervalSince1970 + 60 { credentials = try await api.connect() }
            guard let credentials else { return }
            // Capability is separate from the strict route snapshot so older apps can still read it.
            if let enabled = try? await api.englishAddressSharing(credentials), enabled != englishAddressSharing {
                let previous = englishAddressSharing
                englishAddressSharing = enabled
                do { try persist(state, base: base, revision: revision, pending: pending) }
                catch { englishAddressSharing = previous; throw error }
            }
            if let remote = try await api.routeSnapshot(credentials, since: revision) {
                guard !Task.isCancelled else { return }
                try accept(remote)
            }
            guard conflicts.isEmpty, !Task.isCancelled else { return }
            if pending, let revision {
                let sending = state
                do {
                    let nextRevision = try await api.saveRoutes(sending, revision: revision, credentials: credentials)
                    try persist(state, base: sending, revision: nextRevision, pending: state != sending)
                } catch RoutePreferenceError.conflict(let remote) { try accept(remote) }
            }
            failed = false
            status = !conflicts.isEmpty ? "路线设置有冲突 · 点击处理" : pending ? "路线设置已存本机 · 待同步" : "路线设置已共享"
        } catch {
            if case APIError.unauthorized = error { credentials = nil }
            guard !Task.isCancelled else { return }
            failed = true; status = pending ? "路线设置已存本机 · 待同步" : "路线设置暂未连接 · 将重试"
            if case APIError.response(404, _) = error { status = "路线共享服务尚未就绪 · 本机设置已保留" }
        }
    }
    private func accept(_ remote: RoutePreferenceSnapshot, choices: [String: MergeChoice] = [:]) throws {
        try remote.state.validated(for: state.tripID)
        if !pending { try persist(remote.state, base: remote.state, revision: remote.revision, pending: false); return }
        let (merged, conflicts) = RoutePreferenceMerge.merge(base: base, local: state, remote: remote.state, choices: choices)
        guard conflicts.isEmpty else { self.conflicts = conflicts; remoteConflict = remote; status = "路线设置有冲突 · 点击处理"; return }
        try persist(merged, base: remote.state, revision: remote.revision, pending: merged != remote.state)
        self.conflicts = []; remoteConflict = nil
    }
    func resolve(_ choices: [String: MergeChoice]) {
        guard let remoteConflict, conflicts.allSatisfy({ choices[$0.id] != nil }) else { return }
        do { try accept(remoteConflict, choices: choices); Task { await synchronize() } }
        catch { self.error = error.localizedDescription }
    }
}
