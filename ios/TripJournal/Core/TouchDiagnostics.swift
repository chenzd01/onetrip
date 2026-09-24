import CryptoKit
import Foundation
import os

/// On-device interaction trail. A TestFlight tester has no console, so the app keeps its own
/// short record of what it asked the server, what came back, and what iOS delivered.
/// Device tokens and credentials are only ever stored as the same eight-character
/// SHA-256 prefix the server logs, so the two sides can be lined up without exposing either.
@MainActor final class TouchDiagnostics {
    static let shared = TouchDiagnostics()
    private static let limit = 240
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()
    private let logger = Logger(subsystem: AppIdentity.appBundleID, category: "touch")
    private let file: URL?
    private(set) var entries: [String] = []

    init(directory: URL? = nil) {
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appending(path: "CoupleTouch")
        file = directory?.appending(path: "diagnostics.log")
        if let file, let text = try? String(contentsOf: file, encoding: .utf8) {
            entries = text.split(separator: "\n").suffix(Self.limit).map(String.init)
        }
    }
    static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
    func record(_ name: String, _ fields: [String: String] = [:]) {
        let line = ([Self.stamp.string(from: .now), name] + fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }).joined(separator: " ")
        logger.log("\(line, privacy: .public)")
        entries.append(line)
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        guard let file, let data = entries.joined(separator: "\n").data(using: .utf8) else { return }
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    var report: String { entries.joined(separator: "\n") }
}
