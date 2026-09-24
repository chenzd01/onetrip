import UIKit
import UserNotifications

struct TouchNotificationRoute: Equatable {
    var eventID: String
    var reply: TouchKind?
}

@MainActor final class TouchNotificationBridge {
    static let shared = TouchNotificationBridge()
    var route: ((TouchNotificationRoute) -> Void)? { didSet { drain() } }
    var foregroundNotification: ((String, TouchNotificationSettings) -> Bool)?
    var refresh: (() -> Void)?
    var tokenChanged: (() -> Void)?
    private var pending: [TouchNotificationRoute] = []
    private(set) var token: String?
    private(set) var registrationFailed = false
    func receive(_ value: TouchNotificationRoute) { pending.append(value); drain() }
    private func drain() {
        guard let route else { return }
        let values = pending; pending.removeAll()
        values.forEach(route)
    }
    func registered(_ token: String) {
        self.token = token; registrationFailed = false
        TouchDiagnostics.shared.record("apns.token", ["fingerprint": TouchDiagnostics.fingerprint(token)])
        tokenChanged?()
    }
    func failed() {
        registrationFailed = true
        TouchDiagnostics.shared.record("apns.register-failed")
        tokenChanged?()
    }
}

final class TouchAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: "TOUCH_POKE", title: "弹回去", options: [.authenticationRequired, .foreground]),
            UNNotificationAction(identifier: "TOUCH_HEART", title: "回一颗心", options: [.authenticationRequired, .foreground])
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: "TOUCH", actions: actions, intentIdentifiers: [])])
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        TouchNotificationBridge.shared.registered(deviceToken.map { String(format: "%02x", $0) }.joined())
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        TouchNotificationBridge.shared.failed()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let id = notification.request.content.userInfo["touchEventID"] as? String else { return [.banner, .list, .sound] }
        let settings = await TouchNotificationSettings.current()
        return await MainActor.run {
            let bridge = TouchNotificationBridge.shared
            let present = bridge.foregroundNotification?(id, settings) ?? true
            TouchDiagnostics.shared.record("apns.foreground", ["event": String(id.prefix(8)), "present": present ? "1" : "0"])
            bridge.refresh?()
            return present ? [.banner, .list, .sound] : []
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["touchEventID"] as? String {
            let reply: TouchKind? = response.actionIdentifier == "TOUCH_POKE" ? .poke : response.actionIdentifier == "TOUCH_HEART" ? .heart : nil
            let action = response.actionIdentifier
            Task { @MainActor in
                TouchDiagnostics.shared.record("apns.opened", ["event": String(id.prefix(8)), "action": action == UNNotificationDefaultActionIdentifier ? "open" : action])
            }
            if action != UNNotificationDismissActionIdentifier {
                Task { @MainActor in TouchNotificationBridge.shared.receive(.init(eventID: id, reply: reply)) }
            }
        }
        completionHandler()
    }
}

/// A value snapshot keeps actual system settings visible and presentation decisions testable.
struct TouchNotificationSettings: Equatable, Sendable {
    var authorization: UNAuthorizationStatus = .notDetermined
    var alert: UNNotificationSetting = .notSupported
    var sound: UNNotificationSetting = .notSupported
    var lockScreen: UNNotificationSetting = .notSupported
    var notificationCenter: UNNotificationSetting = .notSupported
    var alertStyle: UNAlertStyle = .none
    var allowsDelivery: Bool { [.authorized, .provisional, .ephemeral].contains(authorization) }
    var showsBanner: Bool { allowsDelivery && authorization != .provisional && alert == .enabled && alertStyle != .none }
    var authorizationDescription: String {
        switch authorization {
        case .authorized: "已允许"
        case .provisional: "安静送达"
        case .ephemeral: "临时允许"
        case .denied: "已关闭"
        default: "尚未询问"
        }
    }
    var bannerDescription: String {
        guard showsBanner else { return "未开启" }
        return alertStyle == .alert ? "持续显示" : "临时显示"
    }
    static func description(_ value: UNNotificationSetting) -> String {
        switch value { case .enabled: "已开启"; case .disabled: "已关闭"; default: "不可用" }
    }
    static func current() async -> Self {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self(authorization: settings.authorizationStatus, alert: settings.alertSetting,
                    sound: settings.soundSetting, lockScreen: settings.lockScreenSetting,
                    notificationCenter: settings.notificationCenterSetting, alertStyle: settings.alertStyle)
    }
}

struct TouchPushRegistration {
    var token: String?
    var failed = false
    @MainActor static func current() -> Self {
        Self(token: TouchNotificationBridge.shared.token, failed: TouchNotificationBridge.shared.registrationFailed)
    }
}
