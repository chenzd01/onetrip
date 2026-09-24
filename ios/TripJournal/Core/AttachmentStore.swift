import Foundation
import CryptoKit

actor AttachmentStore {
    private let directory: URL
    static let maximumSize = 10 * 1024 * 1024
    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    static func detectedType(_ data: Data) -> String? {
        let prefix = Array(data.prefix(12))
        if prefix.starts(with: [0xff, 0xd8, 0xff]) { return "image/jpeg" }
        if prefix.starts(with: [137,80,78,71,13,10,26,10]) { return "image/png" }
        if data.prefix(5) == Data("%PDF-".utf8) { return "application/pdf" }
        if prefix.count == 12 && data.prefix(4) == Data("RIFF".utf8) && data[8..<12] == Data("WEBP".utf8) { return "image/webp" }
        return nil
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func path(_ file: TicketFile) throws -> URL {
        guard file.id.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              let ext = ["image/jpeg":"jpg", "image/png":"png", "image/webp":"webp", "application/pdf":"pdf"][file.type] else { throw TripError.message("附件引用无效") }
        return directory.appending(path: file.id + "." + ext)
    }
    func importFile(_ source: URL) throws -> TicketFile {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...Self.maximumSize).contains(size) else { throw TripError.message("单个附件须在 10 MB 以内") }
        let data = try Data(contentsOf: source)
        guard let type = Self.detectedType(data) else { throw TripError.message("支持 JPG、PNG、WebP 和 PDF；HEIC 请先另存为 JPG") }
        let file = TicketFile(id: Self.hash(data), name: String(source.lastPathComponent.prefix(200)), type: type, size: data.count)
        try save(data, as: file); return file
    }
    func save(_ data: Data, as file: TicketFile) throws {
        guard data.count == file.size, (1...Self.maximumSize).contains(data.count), Self.hash(data) == file.id, Self.detectedType(data) == file.type else { throw TripError.message("附件未完整传输，请重试") }
        try data.write(to: path(file), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func data(for file: TicketFile) throws -> Data {
        let data = try Data(contentsOf: path(file))
        guard data.count == file.size, Self.hash(data) == file.id, Self.detectedType(data) == file.type else { throw TripError.message("本机附件校验失败，需要重新下载") }
        return data
    }
    func verifiedURL(for file: TicketFile) throws -> URL { _ = try data(for: file); return try path(file) }
    func available(_ file: TicketFile) -> Bool { (try? data(for: file)) != nil }
    func export(ticket: Ticket, place: String) throws -> URL {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;") }
        // Resolve every original attachment first; never emit a partial offline ticket.
        let files = try ticket.files.map { ($0, try data(for: $0)) }
        let fields = [("地点",place),("票种",ticket.title),("日期",ticket.date+" "+ticket.time),("人数",String(ticket.quantity)),("平台",ticket.provider),("取票 / 订单码",ticket.reference),("退改截止",ticket.deadline),("备注",ticket.notes)]
        var html = "<!doctype html><html lang='zh-CN'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>离线门票</title><style>body{max-width:760px;margin:24px auto;padding:16px;font:17px/1.7 -apple-system,sans-serif;background:#f7f5ef;color:#294e43}dt{font-size:13px;color:#68756c}dd{margin:0 0 16px;white-space:pre-wrap;overflow-wrap:anywhere}img{max-width:100%;height:auto}a{display:block;padding:12px;color:inherit}section{margin:24px 0}</style><h1>" + escape(place) + " · 门票</h1><p>离线副本，不会自动更新。动态二维码仍需打开原预订平台。</p><dl>"
        for (key,value) in fields { html += "<dt>"+escape(key)+"</dt><dd>"+escape(value)+"</dd>" }; html += "</dl>"
        for (file,data) in files {
            let uri = "data:"+file.type+";base64,"+data.base64EncodedString()
            html += "<section><h2>"+escape(file.name)+"</h2>"
            if file.type.hasPrefix("image/") { html += "<img alt='门票附件' src='"+uri+"'>" }
            html += "<a download='"+escape(file.name)+"' href='"+uri+"'>保存原始附件</a></section>"
        }
        html += "</html>"
        let out = FileManager.default.temporaryDirectory.appending(path: "ticket-"+ticket.id+".html")
        try html.write(to: out, atomically: true, encoding: .utf8); return out
    }
}
struct TicketDraft: Codable, Identifiable {
    var placeID: String
    var ticket: Ticket
    var id: String { ticket.id }
}
