import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor @Observable final class TouchStore {
    static let offlineNote = "碰一下需要自建后端（见 docs/zh/backend.md）；未配置时不会连接网络。"
    private(set) var archive = TouchArchive()
    private(set) var busy = false
    private(set) var refreshing = false
    private(set) var notificationSettings = TouchNotificationSettings()
    var authorization: UNAuthorizationStatus { notificationSettings.authorization }
    private(set) var revoked = false
    private(set) var notificationStatus: String?
    private(set) var notificationConnectionReady = false
    private(set) var needsPairingCode = false
    var error: String?
    var feedback: String?
    var showingSettings = false
    var showingWelcome = false
    var homeVisible = false
    var homeRequest = 0
    var banner: TouchEvent?
    private(set) var animation: TouchEvent?
    private var transport: (any TouchTransport)?
    private let file: URL
    private var foreground = false
    private var polling: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private let readNotificationSettings: @MainActor () async -> TouchNotificationSettings
    private let readPushRegistration: @MainActor () -> TouchPushRegistration
    private var uploadedToken: String?
    private var notificationRetryAt: Date?
    private var notificationRetryCount = 0
    private var updatingNotificationSettings = false
    private var restoring = false
    private var requestedEventID: String?
    var profile: TouchProfile? { archive.profile }
    var paired: Bool { profile?.partnerID != nil && !revoked }
    var events: [TouchEvent] { archive.events.sorted { $0.seq > $1.seq } }
    var waitingHeart: Bool { archive.events.contains { $0.recipient == profile?.memberID && !archive.played.contains($0.id) && $0.kind == .heart } }
    var canSend: Bool { paired && !busy && archive.pending == nil }

    init(directory: URL? = nil, transport: (any TouchTransport)? = nil, bridge: Bool = true,
         notificationSettings: @escaping @MainActor () async -> TouchNotificationSettings = { await TouchNotificationSettings.current() },
         pushRegistration: @escaping @MainActor () -> TouchPushRegistration = { TouchPushRegistration.current() }) {
        readNotificationSettings = notificationSettings
        readPushRegistration = pushRegistration
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "CoupleTouch")
        file = directory.appending(path: "interactions.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { archive = try JSONDecoder().decode(TouchArchive.self, from: Data(contentsOf: file)) }
            archive.prune(now: .now)
            self.transport = try transport ?? TouchAPI(secret: TouchVault.secret())
        } catch { self.error = "互动暂时无法打开，本机记录已保留。" }
        TouchDiagnostics.shared.record("launch", ["bound": archive.profile == nil ? "0" : "1", "paired": archive.profile?.partnerID == nil ? "0" : "1"])
        if bridge {
            let center = TouchNotificationBridge.shared
            center.foregroundNotification = { [weak self] id, settings in
                guard let self else { return true }
                self.notificationSettings = settings
                return self.claimSystemNotification(id)
            }
            center.refresh = { [weak self] in Task { await self?.refresh() } }
            center.tokenChanged = { [weak self] in Task { await self?.updateNotificationSettings(register: false) } }
            center.route = { [weak self] route in Task { await self?.open(route) } }
        }
    }
    private func save() throws {
        archive.prune(now: .now)
        try JSONEncoder().encode(archive).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func call<T: Decodable>(_ action: String, body: [String: String]? = nil, after: Int? = nil) async throws -> T {
        guard let transport else { throw TripError.message("互动暂时无法打开，请稍后重试") }
        return try JSONDecoder().decode(T.self, from: await transport.request(action, body: body, after: after))
    }
    private func describe(_ failure: Error) -> String {
        if case APIError.response(let code, let message) = failure {
            if code == 404 { return "碰一下服务还未就绪，请稍后再来。" }
            return message
        }
        return "暂时没连上，稍后再试一次吧。"
    }
    private func note(_ action: String, _ failure: Error) {
        guard case APIError.response(let code, let message) = failure else {
            TouchDiagnostics.shared.record(action + ".failed", ["transport": "1"]); return
        }
        // A taken slot is not a dead end: the pairing code is the way in, so offer it right away.
        if code == 409 { needsPairingCode = true }
        TouchDiagnostics.shared.record(action + ".refused", ["status": String(code), "reason": message])
    }
    func setForeground(_ active: Bool) {
        foreground = active
        polling?.cancel(); polling = nil
        if !active { bannerTask?.cancel(); banner = nil; return }
        notificationRetryCount = 0; notificationRetryAt = nil
        polling = Task { [weak self] in
            await self?.updateNotificationSettings()
            while !Task.isCancelled {
                await self?.retryNotificationConnectionIfNeeded()
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(self?.error == nil ? 3 : 12)) } catch { return }
            }
        }
    }
    func refresh() async {
        guard !refreshing, !revoked, transport != nil else { return }
        // Only explicitly registered devices poll for interactions.
        guard archive.profile != nil else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let profile: TouchProfile = try await call("status")
            archive.profile = profile
            if profile.inviteExpires == nil { archive.invite = nil }
            var fresh: [TouchEvent] = []
            var more = true
            while more && !Task.isCancelled {
                let feed: TouchFeed = try await call("events", after: archive.cursor)
                for event in feed.events where !archive.events.contains(where: { $0.id == event.id }) {
                    archive.events.append(event)
                    if event.recipient == profile.memberID && !archive.noticed.contains(event.id) { fresh.append(event) }
                }
                archive.cursor = feed.cursor; more = feed.hasMore
            }
            try save()
            if archive.pending == nil { error = nil }
            for event in fresh where foreground && Date.now.timeIntervalSince1970 - event.created < 60 {
                present(event)
            }
        } catch is CancellationError { }
        catch {
            if case APIError.response(403, _) = error { revoked = true }
            self.error = describe(error)
        }
    }
    var bindingStatus: String {
        if revoked { return "这部手机已解绑" }
        if paired { return "两部手机已绑定" }
        guard let profile else { return "这部手机尚未绑定" }
        // Joining with a code only proposes; saying "已绑定" here would be a lie until confirmed.
        if profile.waiting { return "已经把加入请求发过去了，等对方在 TA 的手机上确认" }
        return "这部手机已绑定，等另一部手机加入"
    }
    func presentWelcomeIfNeeded() {
        if profile == nil && archive.welcomeDismissed != true { showingWelcome = true }
    }
    func dismissWelcome() {
        showingWelcome = false
        archive.welcomeDismissed = true
        do { try save() } catch { self.error = "本机暂时无法保存，请稍后重试" }
    }
    func bindDevice() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let profile: TouchProfile = try await call("bind", body: [:])
            archive.profile = profile; revoked = false; archive.welcomeDismissed = true; needsPairingCode = false
            TouchDiagnostics.shared.record("bind.ok", ["member": String(profile.memberID.prefix(8)), "paired": profile.partnerID == nil ? "0" : "1"])
            try save(); await updateNotificationSettings()
        } catch { self.error = describe(error); note("bind", error) }
    }
    func enroll(_ name: String) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let profile: TouchProfile = try await call("enroll", body: ["nickname": name])
            archive.profile = profile; revoked = false
            TouchDiagnostics.shared.record("enroll.ok", ["member": String(profile.memberID.prefix(8))])
            try save(); await updateNotificationSettings()
        } catch { self.error = describe(error); note("enroll", error) }
    }
    func invite(replace: Bool = false) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            archive.invite = try await call("invite", body: replace ? ["replace": "true"] : [:])
            TouchDiagnostics.shared.record("invite.ok", ["replace": replace ? "1" : "0"])
            try save(); await refresh()
        } catch { self.error = describe(error); note("invite", error) }
    }
    func pairing(_ action: String, code: String = "") async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let profile: TouchProfile = try await call(action, body: action == "join" ? ["code": code] : [:])
            archive.profile = profile
            if action == "confirm" || action == "cancel-invite" { archive.invite = nil }
            if action == "join" { needsPairingCode = false }
            TouchDiagnostics.shared.record(action + ".ok", ["paired": profile.partnerID == nil ? "0" : "1", "waiting": profile.waiting ? "1" : "0"])
            try save(); await refresh()
        } catch { self.error = describe(error); note(action, error) }
    }
    func resetRevokedDevice() {
        guard revoked else { return }
        do {
            transport = TouchAPI(secret: try TouchVault.secret(reset: true))
            archive = TouchArchive(); try save()
            revoked = false; uploadedToken = nil; error = nil
        } catch { self.error = "暂时无法重设设备，请稍后重试。" }
    }
    func send(_ kind: TouchKind, id: String = UUID().uuidString) async {
        guard canSend else { return }
        archive.pending = TouchCommand(id: id, kind: kind)
        do { try save() } catch { archive.pending = nil; self.error = "这一下还没发出去，本机暂时无法保存。"; return }
        await attemptPending(checkFirst: false)
    }
    func retry() async { await attemptPending(checkFirst: true) }
    func discardPending() {
        let pending = archive.pending
        archive.pending = nil
        do { try save(); error = nil; feedback = nil } catch { archive.pending = pending; self.error = "本机暂时无法保存，请稍后再试。" }
    }
    private func attemptPending(checkFirst: Bool) async {
        guard let pending = archive.pending, !busy else { return }
        busy = true; error = nil; feedback = "正在把小动作递过去…"
        defer { busy = false }
        do {
            var event: TouchEvent?
            var receipt: TouchReceipt?
            if checkFirst {
                let result: TouchReceipt = try await call("events/" + pending.id)
                event = result.event; receipt = result
            }
            if event == nil {
                let result: TouchReceipt = try await call("send", body: ["id": pending.id, "kind": pending.kind.rawValue])
                event = result.event; receipt = result
            }
            guard let event else { throw TripError.message("互动响应无效") }
            if !archive.events.contains(where: { $0.id == event.id }) { archive.events.append(event) }
            archive.pending = nil
            do { try save() } catch { archive.pending = pending; throw error }
            feedback = receipt?.acknowledgement(for: pending.kind) ?? pending.kind.acknowledgement
            TouchDiagnostics.shared.record("send.ok", ["event": String(event.id.prefix(8)), "kind": event.kind.rawValue, "notification": receipt?.notificationState ?? receipt?.alert ?? "-"])
        } catch {
            feedback = "这一下还没确认发出。"
            self.error = describe(error); note("send", error)
        }
    }
    func homeAppeared() {
        banner = nil
        let requested = events.first { $0.id == requestedEventID && !archive.played.contains($0.id) }
        requestedEventID = nil
        if let event = requested ?? events.first(where: { $0.recipient == profile?.memberID && !archive.played.contains($0.id) }) {
            play(event)
            // Opening a batch never drains a queue of old animations.
            archive.played.formUnion(events.filter { $0.recipient == profile?.memberID }.map(\.id))
            try? save()
        }
    }
    func focusHome() { showingSettings = false; homeRequest += 1 }
    func dismissBanner() { banner = nil }
    /// Polling and animation never claim the system notification: APNs may arrive later.
    func claimSystemNotification(_ id: String) -> Bool {
        guard archive.systemNotified?[id] == nil else { return false }
        if archive.systemNotified == nil { archive.systemNotified = [:] }
        archive.systemNotified?[id] = Date.now.timeIntervalSince1970
        if notificationSettings.showsBanner && banner?.id == id { dismissBanner() }
        try? save()
        return true
    }
    private func usesSystemBanner(for event: TouchEvent) -> Bool {
        notificationSettings.showsBanner && (notificationConnectionReady || archive.systemNotified?[event.id] != nil)
    }
    private func present(_ event: TouchEvent) {
        guard !archive.noticed.contains(event.id) else { return }
        archive.noticed.insert(event.id)
        if !usesSystemBanner(for: event) {
            banner = event
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            bannerTask?.cancel()
            bannerTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(6)) } catch { return }
                self?.banner = nil
            }
        }
        if homeVisible { play(event) }
        TouchDiagnostics.shared.record("incoming.shown", ["event": String(event.id.prefix(8)), "kind": event.kind.rawValue, "card": usesSystemBanner(for: event) ? "0" : "1", "dot": homeVisible ? "1" : "0"])
        try? save()
    }
    private func play(_ event: TouchEvent) {
        guard !archive.played.contains(event.id) else { return }
        archive.played.insert(event.id); animation = event
        if archive.pending == nil && !busy && banner == nil && !usesSystemBanner(for: event) { feedback = event.message }
        try? save()
    }
    func open(_ route: TouchNotificationRoute) async {
        focusHome()
        guard !restoring else { return }; restoring = true
        defer { restoring = false }
        do {
            let receipt: TouchReceipt = try await call("events/" + route.eventID)
            guard let event = receipt.event, event.recipient == profile?.memberID else {
                feedback = "这个小动作已经收进回忆里了。"; return
            }
            if !archive.events.contains(where: { $0.id == event.id }) { archive.events.append(event) }
            requestedEventID = event.id
            if homeVisible { homeAppeared() }
            if let kind = route.reply {
                guard archive.pending == nil else { error = "还有一个小动作待确认，先处理它再回复吧。"; return }
                await send(kind, id: "reply-" + route.eventID + "-" + kind.rawValue)
            }
        } catch { self.error = describe(error) }
    }
    func allowNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await updateNotificationSettings()
        } catch { notificationStatus = "暂时无法开启通知，仍可以在 App 内接住小动作。" }
    }
    func retryNotificationConnectionIfNeeded(now: Date = .now) async {
        guard foreground, let retryAt = notificationRetryAt, retryAt <= now else { return }
        notificationRetryAt = nil
        await updateNotificationSettings()
    }
    private func scheduleNotificationRetry() {
        guard notificationRetryAt == nil else { return }
        let delays: [TimeInterval] = [3, 10, 30, 60]
        guard notificationRetryCount < delays.count else { return }
        notificationRetryAt = Date.now.addingTimeInterval(delays[notificationRetryCount])
        notificationRetryCount += 1
    }
    func updateNotificationSettings(register: Bool = true) async {
        guard !updatingNotificationSettings else { scheduleNotificationRetry(); return }
        updatingNotificationSettings = true
        defer { updatingNotificationSettings = false }
        notificationSettings = await readNotificationSettings()
        let allowed = notificationSettings.allowsDelivery
        if allowed && register { UIApplication.shared.registerForRemoteNotifications() }
        let registration = readPushRegistration()
        notificationConnectionReady = allowed && registration.token?.isEmpty == false && uploadedToken == registration.token && !registration.failed
        notificationStatus = allowed && !notificationConnectionReady ? "通知连接暂未就绪，使用 App 时仍会用卡片提醒。" : nil
        guard profile != nil, !revoked else { return }
        guard let token = allowed ? registration.token : "" else { scheduleNotificationRetry(); return }
        if uploadedToken == token {
            if allowed && !notificationConnectionReady { scheduleNotificationRetry() }
            else { notificationRetryAt = nil; notificationRetryCount = 0 }
            return
        }
        // Release/TestFlight use production APNs; simulator and Debug use sandbox.
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            struct OK: Decodable { var ok: Bool }
            let _: OK = try await call("device", body: ["token": token, "environment": environment])
            uploadedToken = token
            let current = readPushRegistration()
            notificationConnectionReady = allowed && !token.isEmpty && current.token == token && !current.failed
            if !allowed || notificationConnectionReady {
                notificationStatus = nil; notificationRetryAt = nil; notificationRetryCount = 0
            } else { scheduleNotificationRetry() }
            TouchDiagnostics.shared.record("device.registered", ["fingerprint": token.isEmpty ? "cleared" : TouchDiagnostics.fingerprint(token), "environment": environment, "authorization": String(authorization.rawValue)])
        } catch {
            notificationConnectionReady = false
            notificationStatus = "通知连接暂未就绪，使用 App 时仍会用卡片提醒。"
            scheduleNotificationRetry()
            note("device", error)
        }
    }
}
