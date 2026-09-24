import XCTest
import UserNotifications
@testable import TripJournal

actor TouchMockTransport: TouchTransport {
    enum FailureMode: Sendable { case none, beforeAcceptance, afterAcceptance }
    var mode: FailureMode = .none
    var posts = 0
    var queries = 0
    var bindings = 0
    var bindRefusal: Int?
    var deviceFailure = false
    var devicePosts = 0
    var stored: [TouchEvent] = []
    let profile = TouchProfile(memberID: "me", nickname: "我", partnerName: "你", partnerID: "partner", waiting: false)
    func setFailure(_ value: FailureMode) { mode = value }
    func setBindRefusal(_ status: Int?) { bindRefusal = status }
    func insert(_ event: TouchEvent) { stored.append(event) }
    func bindingCount() -> Int { bindings }
    func setDeviceFailure(_ value: Bool) { deviceFailure = value }
    func deviceCount() -> Int { devicePosts }
    func counts() -> (Int, Int) { (posts, queries) }
    func request(_ action: String, body: [String: String]?, after: Int?) async throws -> Data {
        let encoder = JSONEncoder()
        if action == "bind" {
            bindings += 1
            if let bindRefusal { throw APIError.response(bindRefusal, "第一部手机已经绑定了。请让 TA 生成配对码，在下面输入就能加入。") }
            return try encoder.encode(profile)
        }
        if action == "status" || action == "enroll" { return try encoder.encode(profile) }
        if action == "device" {
            devicePosts += 1
            if deviceFailure { throw URLError(.notConnectedToInternet) }
            return Data("{\"ok\":true}".utf8)
        }
        if action == "events" {
            let events = stored.filter { $0.seq > (after ?? 0) }
            return try encoder.encode(TouchFeed(events: events, cursor: events.last?.seq ?? after ?? 0, hasMore: false))
        }
        if action.hasPrefix("events/") {
            queries += 1
            return try encoder.encode(TouchReceipt(event: stored.first { $0.id == String(action.dropFirst(7)) }))
        }
        if action == "send" {
            posts += 1
            if mode == .beforeAcceptance { throw URLError(.notConnectedToInternet) }
            let id = body!["id"]!
            let event = stored.first { $0.id == id } ?? TouchEvent(seq: stored.count+1, id: id, sender: "me", recipient: "partner", kind: TouchKind(rawValue: body!["kind"]!)!, name: "我", created: Date.now.timeIntervalSince1970)
            if !stored.contains(where: { $0.id == id }) { stored.append(event) }
            if mode == .afterAcceptance { throw URLError(.timedOut) }
            return try encoder.encode(TouchReceipt(event: event))
        }
        throw URLError(.badURL)
    }
}

@MainActor final class TouchTests: XCTestCase {
    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
    func testWelcomeDismissalDoesNotBindAndManualConfirmationSurvivesRestart() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        let store = TouchStore(directory: directory, transport: mock, bridge: false)
        store.presentWelcomeIfNeeded()
        XCTAssertTrue(store.showingWelcome)
        store.dismissWelcome()
        XCTAssertNil(store.profile)
        let untouched = await mock.bindingCount()
        XCTAssertEqual(untouched, 0)
        let reopened = TouchStore(directory: directory, transport: mock, bridge: false)
        reopened.presentWelcomeIfNeeded()
        XCTAssertFalse(reopened.showingWelcome)
        await reopened.bindDevice()
        XCTAssertTrue(reopened.paired)
        let confirmed = await mock.bindingCount()
        XCTAssertEqual(confirmed, 1)
        let bound = TouchStore(directory: directory, transport: mock, bridge: false)
        bound.presentWelcomeIfNeeded()
        XCTAssertFalse(bound.showingWelcome)
        XCTAssertTrue(bound.paired)
    }
    func testBallCanTriggerTowardEveryScreenEdgeWithoutShortTapSending() {
        let bounds = CGRect(x: 0, y: 0, width: 402, height: 874)
        let origin = CGPoint(x: 360, y: 84)
        for delta in [CGPoint(x: -80, y: 0), CGPoint(x: 32, y: 0), CGPoint(x: 0, y: -60), CGPoint(x: 0, y: 80), CGPoint(x: -60, y: 60)] {
            XCTAssertTrue(TouchBallActivation.isArmed(delta: delta, origin: origin, bounds: bounds))
        }
        for delta in [CGPoint.zero, CGPoint(x: 8, y: 0), CGPoint(x: 0, y: 20), CGPoint(x: -20, y: 0)] {
            XCTAssertFalse(TouchBallActivation.isArmed(delta: delta, origin: origin, bounds: bounds))
        }
    }
    func testLostResponseIsQueriedBeforeRetryWithoutSendingTwice() async throws {
        let mock = TouchMockTransport()
        let store = TouchStore(directory: try directory(), transport: mock, bridge: false)
        await store.enroll("我")
        await mock.setFailure(.afterAcceptance)
        await store.send(.heart, id: "uncertain")
        XCTAssertEqual(store.archive.pending?.id, "uncertain")
        XCTAssertNotEqual(store.feedback, TouchKind.heart.acknowledgement)
        await mock.setFailure(.none)
        await store.retry()
        XCTAssertNil(store.archive.pending)
        XCTAssertEqual(store.feedback, TouchKind.heart.acknowledgement)
        let counts = await mock.counts()
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testOfflinePendingSurvivesRestartButNeverAutoSends() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        let store = TouchStore(directory: directory, transport: mock, bridge: false)
        await store.enroll("我"); await mock.setFailure(.beforeAcceptance)
        await store.send(.poke, id: "offline")
        let reopened = TouchStore(directory: directory, transport: mock, bridge: false)
        await mock.setFailure(.none)
        await reopened.refresh()
        XCTAssertEqual(reopened.archive.pending?.id, "offline")
        let before = await mock.counts(); XCTAssertEqual(before.0, 1)
        await reopened.retry()
        let after = await mock.counts(); XCTAssertEqual(after.0, 2); XCTAssertEqual(after.1, 1)
        XCTAssertNil(reopened.archive.pending)
    }
    func testIncomingTouchUsesFallbackWhenSystemBannerIsDisabled() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        let store = TouchStore(directory: directory, transport: mock, bridge: false, notificationSettings: { TouchNotificationSettings(authorization: .denied) })
        await store.enroll("我")
        // The fallback is required even while the animation control is visible.
        store.homeVisible = true
        await mock.insert(TouchEvent(seq: 1, id: "incoming", sender: "partner", recipient: "me", kind: .poke, name: "你", created: Date.now.timeIntervalSince1970))
        store.setForeground(true)
        let deadline = Date.now.addingTimeInterval(5)
        while store.banner == nil && Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.banner?.id, "incoming")
        XCTAssertEqual(store.animation?.id, "incoming")
        await mock.insert(TouchEvent(seq: 2, id: "incoming-again", sender: "partner", recipient: "me", kind: .heart, name: "你", created: Date.now.timeIntervalSince1970))
        await store.refresh()
        XCTAssertEqual(store.banner?.id, "incoming-again", "A different event must not be suppressed by the former three-second coalescing window")
        XCTAssertEqual(store.animation?.id, "incoming-again")
        store.setForeground(false)
        XCTAssertNil(store.banner)
    }
    func testPollingBeforePushDoesNotConsumeSystemNotification() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        let settings = TouchNotificationSettings(authorization: .authorized, alert: .enabled, sound: .enabled,
                                                 lockScreen: .enabled, notificationCenter: .enabled, alertStyle: .banner)
        let store = TouchStore(directory: directory, transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { TouchPushRegistration(token: "test-token") })
        await store.enroll("我")
        store.homeVisible = true
        await mock.insert(TouchEvent(seq: 1, id: "poll-first", sender: "partner", recipient: "me", kind: .poke, name: "你", created: Date.now.timeIntervalSince1970))
        store.setForeground(true)
        defer { store.setForeground(false) }
        let deadline = Date.now.addingTimeInterval(5)
        while store.animation == nil && Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(store.animation?.id, "poll-first")
        XCTAssertNil(store.banner, "System banner and fallback card must not compete")
        XCTAssertNil(store.feedback, "Receiving an event through the system-banner path must not create a second toast")
        XCTAssertTrue(store.archive.noticed.contains("poll-first"))
        XCTAssertTrue(store.claimSystemNotification("poll-first"), "Polling may not swallow a delayed push")
        XCTAssertFalse(store.claimSystemNotification("poll-first"), "Duplicate push must not notify twice")
        let reopened = TouchStore(directory: directory, transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { TouchPushRegistration(token: "test-token") })
        XCTAssertFalse(reopened.claimSystemNotification("poll-first"), "Notification dedup survives relaunch")
        reopened.homeAppeared()
        XCTAssertNil(reopened.animation, "System notification may not replay an already played animation")
    }
    func testPushBeforeFeedRetainsItsIndependentMarkerAndDoesNotBlockAnimation() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        let settings = TouchNotificationSettings(authorization: .authorized, alert: .enabled, alertStyle: .banner)
        let store = TouchStore(directory: directory, transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { TouchPushRegistration(token: "test-token") })
        await store.enroll("我")
        XCTAssertTrue(store.claimSystemNotification("push-first"))
        let reopened = TouchStore(directory: directory, transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { TouchPushRegistration(token: "test-token") })
        XCTAssertFalse(reopened.claimSystemNotification("push-first"), "Saving before the event feed must retain the push marker")
        await mock.insert(TouchEvent(seq: 1, id: "push-first", sender: "partner", recipient: "me", kind: .heart, name: "你", created: Date.now.timeIntervalSince1970))
        await reopened.updateNotificationSettings(register: false)
        await reopened.refresh()
        reopened.homeAppeared()
        XCTAssertEqual(reopened.animation?.id, "push-first")
        XCTAssertNil(reopened.feedback, "A push received before the event feed must not create a duplicate toast when its animation plays")
    }
    func testEnabledBannersStillUseFallbackWhenNotificationConnectionIsUnavailable() async throws {
        for registration in [TouchPushRegistration(token: nil), TouchPushRegistration(token: "token", failed: true), TouchPushRegistration(token: "token")] {
            let mock = TouchMockTransport()
            await mock.setDeviceFailure(true)
            let settings = TouchNotificationSettings(authorization: .authorized, alert: .enabled, alertStyle: .banner)
            let store = TouchStore(directory: try directory(), transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { registration })
            await store.enroll("我")
            await mock.insert(TouchEvent(seq: 1, id: "unconnected", sender: "partner", recipient: "me", kind: .poke, name: "你", created: Date.now.timeIntervalSince1970))
            store.setForeground(true)
            let deadline = Date.now.addingTimeInterval(5)
            while store.banner == nil && Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertFalse(store.notificationConnectionReady)
            XCTAssertFalse(store.homeVisible)
            XCTAssertEqual(store.banner?.id, "unconnected", "A non-home screen still needs its fallback when APNs cannot reach this installation")
            XCTAssertTrue(store.claimSystemNotification("unconnected"), "Polling must not claim a late system notification")
            XCTAssertNil(store.banner, "A real APNs notification replaces the fallback for this event")
            store.setForeground(false)
        }
    }
    func testNotificationConnectionRetriesAreBoundedAndRecoverWhileForeground() async throws {
        let mock = TouchMockTransport()
        await mock.setDeviceFailure(true)
        let settings = TouchNotificationSettings(authorization: .authorized, alert: .enabled, alertStyle: .banner)
        let store = TouchStore(directory: try directory(), transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { TouchPushRegistration(token: "retry-token") })
        await store.enroll("我")
        let enrolled = await mock.deviceCount()
        store.setForeground(true)
        defer { store.setForeground(false) }
        let deadline = Date.now.addingTimeInterval(5)
        while await mock.deviceCount() == enrolled && Date.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        // Let the currently executing settings request schedule its retry.
        try await Task.sleep(for: .milliseconds(50))
        let before = await mock.deviceCount()
        for _ in 0..<6 { await store.retryNotificationConnectionIfNeeded(now: .distantFuture) }
        let after = await mock.deviceCount()
        XCTAssertEqual(after - before, 4, "One foreground session performs at most four automatic reconnection retries")
        XCTAssertFalse(store.notificationConnectionReady)
        await mock.setDeviceFailure(false)
        // An explicit settings refresh starts a fresh connection attempt without reopening the app.
        await store.updateNotificationSettings(register: false)
        XCTAssertTrue(store.notificationConnectionReady)
        XCTAssertNil(store.notificationStatus)
    }
    func testNotificationUploadRecoversOnAutomaticForegroundRetry() async throws {
        let mock = TouchMockTransport()
        await mock.setDeviceFailure(true)
        let settings = TouchNotificationSettings(authorization: .authorized, alert: .enabled, alertStyle: .banner)
        let store = TouchStore(directory: try directory(), transport: mock, bridge: false, notificationSettings: { settings }, pushRegistration: { TouchPushRegistration(token: "retry-token") })
        await store.enroll("我")
        store.setForeground(true)
        defer { store.setForeground(false) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(store.notificationConnectionReady)
        await mock.setDeviceFailure(false)
        await store.retryNotificationConnectionIfNeeded(now: .distantFuture)
        XCTAssertTrue(store.notificationConnectionReady)
        XCTAssertNil(store.notificationStatus)
    }
    func testNotificationSettingsDistinguishQuietDeliveryFromBannerPermission() {
        var settings = TouchNotificationSettings(authorization: .provisional, alert: .enabled, alertStyle: .banner)
        XCTAssertTrue(settings.allowsDelivery)
        XCTAssertFalse(settings.showsBanner)
        XCTAssertEqual(settings.authorizationDescription, "安静送达")
        settings.authorization = .authorized
        XCTAssertTrue(settings.showsBanner)
        settings.alertStyle = .none
        XCTAssertFalse(settings.showsBanner)
        settings.alertStyle = .alert
        XCTAssertEqual(settings.bannerDescription, "持续显示")
        settings.alert = .disabled
        XCTAssertFalse(settings.showsBanner)
    }
    func testReceiptNeverClaimsAppleAcceptanceMeansDeliveredOrSounded() {
        XCTAssertEqual(TouchReceipt(notificationState: "accepted").acknowledgement(for: .poke), "弹出去了，已提交系统通知")
        XCTAssertEqual(TouchReceipt(notificationState: "pending").acknowledgement(for: .heart), "爱心送出啦，正在发送系统通知")
        XCTAssertEqual(TouchReceipt(notificationState: "uncertain").acknowledgement(for: .poke), "弹出去了，系统通知状态暂未确认")
        XCTAssertEqual(TouchReceipt(notificationState: "not-queued").acknowledgement(for: .poke), "弹出去了，这次未安排系统通知")
    }
    func testOldArchiveWithoutNotificationMarkersStillLoads() throws {
        let data = Data(#"{"events":[],"cursor":0,"noticed":[],"played":[]}"#.utf8)
        let archive = try JSONDecoder().decode(TouchArchive.self, from: data)
        XCTAssertNil(archive.systemNotified)
    }
    func testRefusedBindingOffersThePairingCode() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        await mock.setBindRefusal(409)
        let store = TouchStore(directory: directory, transport: mock, bridge: false)
        await store.bindDevice()
        XCTAssertTrue(store.needsPairingCode, "A taken slot must offer the pairing code")
        XCTAssertNil(store.profile)
        await mock.setBindRefusal(nil)
        await store.bindDevice()
        XCTAssertFalse(store.needsPairingCode)
        XCTAssertTrue(store.paired)
    }
    func testRepeatedFeedAndOpenPlayOnlyOnceAcrossRestart() async throws {
        let mock = TouchMockTransport(), directory = try directory()
        let event = TouchEvent(seq: 1, id: "gift", sender: "partner", recipient: "me", kind: .heart, name: "你", created: Date.now.timeIntervalSince1970)
        await mock.insert(event)
        let store = TouchStore(directory: directory, transport: mock, bridge: false)
        await store.enroll("我"); await store.refresh(); await store.refresh()
        XCTAssertEqual(store.events.count, 1); XCTAssertTrue(store.waitingHeart)
        store.homeAppeared()
        XCTAssertEqual(store.animation?.id, "gift"); XCTAssertFalse(store.waitingHeart)
        let reopened = TouchStore(directory: directory, transport: mock, bridge: false)
        await reopened.open(.init(eventID: "gift"))
        XCTAssertNil(reopened.animation)
    }
    func testNotificationReplyUsesDeterministicIDAndChecksRecipient() async throws {
        let mock = TouchMockTransport()
        await mock.insert(TouchEvent(seq: 1, id: "gift", sender: "partner", recipient: "me", kind: .heart, name: "你", created: Date.now.timeIntervalSince1970))
        let store = TouchStore(directory: try directory(), transport: mock, bridge: false)
        await store.enroll("我")
        await store.open(.init(eventID: "gift", reply: .poke))
        await store.open(.init(eventID: "gift", reply: .poke))
        XCTAssertEqual(store.events.filter { $0.id == "reply-gift-poke" }.count, 1)
        let before = await mock.counts()
        await store.open(.init(eventID: "reply-gift-poke", reply: .heart))
        let after = await mock.counts()
        XCTAssertEqual(before.0, after.0)
    }
    func testNotificationFocusesHomeAndWaitsForVisibleControl() async throws {
        let mock = TouchMockTransport()
        await mock.insert(TouchEvent(seq: 1, id: "route", sender: "partner", recipient: "me", kind: .poke, name: "你", created: Date.now.timeIntervalSince1970))
        let store = TouchStore(directory: try directory(), transport: mock, bridge: false)
        await store.enroll("我")
        store.showingSettings = true
        await store.open(.init(eventID: "route"))
        XCTAssertFalse(store.showingSettings)
        XCTAssertEqual(store.homeRequest, 1)
        XCTAssertNil(store.animation)
        XCTAssertFalse(store.archive.played.contains("route"))
        store.homeAppeared()
        XCTAssertEqual(store.animation?.id, "route")
        XCTAssertTrue(store.archive.played.contains("route"))
    }
    func testSevenDayRetentionPrunesAnimationAndNoticeMarkers() {
        let now = Date.now
        let event = TouchEvent(seq: 1, id: "old", sender: "a", recipient: "b", kind: .poke, name: "a", created: now.timeIntervalSince1970 - 8*86400)
        var archive = TouchArchive(events: [event], noticed: ["old"], played: ["old"])
        archive.prune(now: now)
        XCTAssertTrue(archive.events.isEmpty); XCTAssertTrue(archive.played.isEmpty); XCTAssertTrue(archive.noticed.isEmpty)
    }
    func testRealHTTPPairingFeedAndPlanIsolation() async throws {
        guard let raw = ProcessInfo.processInfo.environment["TRIP_INTEGRATION_URL"], let endpoint = URL(string: raw), endpoint.host == "127.0.0.1" else { throw XCTSkip("Requires isolated loopback server") }
        let api = TripAPI(endpoint: endpoint, accessKey: String(repeating: "t", count: 48))
        let credentials = try await api.connect()
        let before = try await api.snapshot(credentials, since: nil)
        let a = TouchAPI(secret: UUID().uuidString + UUID().uuidString, api: api)
        let b = TouchAPI(secret: UUID().uuidString + UUID().uuidString, api: api)
        let decoder = JSONDecoder()
        let first = try decoder.decode(TouchProfile.self, from: await a.request("bind", body: [:]))
        XCTAssertNil(first.partnerID)
        // The second slot is code-gated, so nobody else running this build can take it.
        do {
            _ = try await b.request("bind", body: [:])
            XCTFail("Expected the taken pair to refuse a second tap binding")
        } catch APIError.response(let code, _) {
            XCTAssertEqual(code, 409)
        }
        let invite = try decoder.decode(TouchInvite.self, from: await a.request("invite", body: [:]))
        // A refused bind registers nothing, so the joining phone enrolls first, as the app does.
        _ = try await b.request("enroll", body: ["nickname": "旅伴乙"])
        let joined = try decoder.decode(TouchProfile.self, from: await b.request("join", body: ["code": invite.code]))
        XCTAssertNil(joined.partnerID)
        _ = try await a.request("confirm", body: [:])
        let second = try decoder.decode(TouchProfile.self, from: await b.request("status"))
        XCTAssertEqual(second.partnerID, first.memberID)
        // Empty-token upload must encode JSON null and release an old notification token.
        let cleared = try await a.request("device", body: ["token": "", "environment": "sandbox"])
        XCTAssertEqual((try JSONSerialization.jsonObject(with: cleared) as? [String: Bool])?["ok"], true)
        let paired = try decoder.decode(TouchProfile.self, from: await a.request("status"))
        XCTAssertEqual(paired.partnerID, second.memberID)
        let id = UUID().uuidString
        let sent = try decoder.decode(TouchReceipt.self, from: await a.request("send", body: ["id": id, "kind": "heart"]))
        let retry = try decoder.decode(TouchReceipt.self, from: await a.request("send", body: ["id": id, "kind": "heart"]))
        XCTAssertEqual(sent.event, retry.event)
        XCTAssertEqual(sent.alert, retry.alert)
        XCTAssertEqual(sent.alert, "silent")
        let feed = try decoder.decode(TouchFeed.self, from: await b.request("events", after: 0))
        XCTAssertEqual(feed.events.map(\.id), [id])
        let after = try await api.snapshot(credentials, since: nil)
        XCTAssertEqual(before?.revision, after?.revision)
        XCTAssertEqual(try before.map { try JSONValue.wrap($0.state) }, try after.map { try JSONValue.wrap($0.state) })
    }
}
