import SwiftUI

enum PlaceSource: Equatable {
    case xiaohongshu, publicInformation, reference

    static func classify(_ url: URL) -> Self {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host?.lowercased() else { return .reference }
        if ["xiaohongshu.com", "www.xiaohongshu.com", "xhslink.com", "www.xhslink.com"].contains(host) { return .xiaohongshu }
        // Government domains (".gov", ".gov.xx") are public information in every destination.
        let labels = host.split(separator: ".")
        if labels.last == "gov" || (labels.count >= 3 && labels[labels.count - 2] == "gov") { return .publicInformation }
        return .reference
    }
    var title: String {
        switch self {
        case .xiaohongshu: "小红书攻略"
        case .publicInformation: "官方公共资料"
        case .reference: "第三方参考"
        }
    }
    var icon: String { self == .xiaohongshu ? "book.closed.fill" : self == .reference ? "link" : "building.2" }
    var color: Color { self == .xiaohongshu ? TripStyle.coral : TripStyle.green }
}

struct PlaceSourceLink: View {
    let url: URL
    private var source: PlaceSource { .classify(url) }
    var body: some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Image(systemName: source.icon).foregroundStyle(source.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source == .xiaohongshu ? "在小红书查看原文" : source.title).font(.subheadline.weight(.semibold))
                    if let host = url.host { Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(source.color)
            }.padding(16).background(source.color.opacity(0.07), in: .rect(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}
