import Foundation
import UIKit

enum ExternalLinks {
    static func xiaohongshuNoteURL(_ url: URL) -> URL? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(),
              host == "xiaohongshu.com" || host.hasSuffix(".xiaohongshu.com"),
              url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let noteID: String?
        if parts.count == 2, ["explore", "search_result"].contains(parts[0]) { noteID = parts[1] }
        else if parts.count == 3, parts[0] == "discovery", parts[1] == "item" { noteID = parts[2] }
        else { noteID = nil }
        guard let noteID, noteID.range(of: "^[0-9a-fA-F]{24}$", options: .regularExpression) != nil else { return nil }
        // The platform's getNoteDeeplink uses xhsdiscover://item/<noteId>.
        // Keep the original signed query intact; never replace a note with the home route.
        var destination = URLComponents()
        destination.scheme = "xhsdiscover"
        destination.host = "item"
        destination.path = "/" + noteID
        destination.percentEncodedQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        return destination.url
    }

    @MainActor static func open(_ url: URL, using opener: (URL, Bool) async -> Bool = systemOpen) async -> Bool {
        if let noteURL = xiaohongshuNoteURL(url), await opener(noteURL, false) { return true }
        // Universal links go straight to installed apps. A rejected handoff keeps
        // the exact original URL for the browser, including booking/share parameters.
        if await opener(url, true) { return true }
        return await opener(url, false)
    }

    @MainActor private static func systemOpen(_ url: URL, universalOnly: Bool) async -> Bool {
        await UIApplication.shared.open(url, options: universalOnly ? [.universalLinksOnly: true] : [:])
    }
}
