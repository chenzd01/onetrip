import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    static func wrap<T: Encodable>(_ value: T) throws -> Self { try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value)) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
    var readable: String {
        switch self {
        case .string(let s): s
        case .bool(let b): b ? "已勾选" : "未勾选"
        case .null: "空"
        default: String(data: (try? JSONEncoder().encode(self)) ?? Data(), encoding: .utf8) ?? ""
        }
    }
}
struct MergeConflict: Identifiable, Sendable {
    var path: String
    var local: JSONValue?
    var remote: JSONValue?
    var id: String { path }
}
enum MergeChoice: String, Sendable { case local, remote }
struct MergeResult: Sendable { var value: JSONValue; var conflicts: [MergeConflict] }

enum PlanMerge {
    static func merge(base: JSONValue, local: JSONValue, remote: JSONValue, choices: [String: MergeChoice] = [:]) -> MergeResult {
        var conflicts: [MergeConflict] = []
        func conflict(_ path: String, _ l: JSONValue?, _ r: JSONValue?) -> JSONValue? {
            if let choice = choices[path] { return choice == .local ? l : r }
            conflicts.append(.init(path: path, local: l, remote: r)); return l
        }
        func identifier(_ value: JSONValue) -> String? {
            guard case .object(let object) = value else { return nil }
            for key in ["uid", "id", "date"] {
                if case .string(let id) = object[key] { return id }
            }
            return nil
        }
        func walk(_ b: JSONValue?, _ l: JSONValue?, _ r: JSONValue?, _ path: String) -> JSONValue? {
            if l == r { return l }
            if l == b { return r }
            if r == b { return l }
            if case .object(let lo) = l, case .object(let ro) = r {
                let bo: [String: JSONValue]
                if case .object(let existing) = b { bo = existing }
                else if b == nil && lo["id"] == nil && lo["uid"] == nil && ro["id"] == nil && ro["uid"] == nil { bo = [:] }
                else { return conflict(path, l, r) }
                var out: [String: JSONValue] = [:]
                for key in Set(bo.keys).union(lo.keys).union(ro.keys).sorted() {
                    out[key] = walk(bo[key], lo[key], ro[key], path + "/" + key)
                }
                return .object(out)
            }
            if case .array(let ba) = b, case .array(let la) = l, case .array(let ra) = r {
                let bi = ba.compactMap(identifier), li = la.compactMap(identifier), ri = ra.compactMap(identifier)
                guard bi.count == ba.count, li.count == la.count, ri.count == ra.count,
                      Set(bi).count == bi.count, Set(li).count == li.count, Set(ri).count == ri.count else {
                    return conflict(path, l, r)
                }
                let bd = Dictionary(uniqueKeysWithValues: zip(bi, ba)), ld = Dictionary(uniqueKeysWithValues: zip(li, la)), rd = Dictionary(uniqueKeysWithValues: zip(ri, ra))
                var merged: [String: JSONValue] = [:]
                for id in Set(bi).union(li).union(ri).sorted() {
                    merged[id] = walk(bd[id], ld[id], rd[id], path + "/" + id)
                }
                let ids = Set(merged.keys)
                let baseline = bi.filter { ids.contains($0) }
                let localOrder = li.filter { ids.contains($0) }
                let remoteOrder = ri.filter { ids.contains($0) }
                let common = Set(baseline).intersection(localOrder).intersection(remoteOrder)
                let bOrder = baseline.filter { common.contains($0) }
                let lOrder = localOrder.filter { common.contains($0) }
                let rOrder = remoteOrder.filter { common.contains($0) }
                var order: [String]
                if lOrder == rOrder || lOrder == bOrder { order = remoteOrder }
                else if rOrder == bOrder { order = localOrder }
                else {
                    let chosen = conflict(path + "/排序", .array(localOrder.map(JSONValue.string)), .array(remoteOrder.map(JSONValue.string)))
                    order = chosen == .array(remoteOrder.map(JSONValue.string)) ? remoteOrder : localOrder
                }
                // Distinct insertions retain their nearest surviving predecessor.
                for source in [remoteOrder, localOrder] {
                    for (i, id) in source.enumerated() where !order.contains(id) {
                        if let predecessor = source[..<i].last(where: { order.contains($0) }), let index = order.firstIndex(of: predecessor) { order.insert(id, at: index + 1) }
                        else { order.insert(id, at: 0) }
                    }
                }
                return .array(order.compactMap { merged[$0] })
            }
            return conflict(path, l, r)
        }
        let value = walk(base, local, remote, "行程") ?? local
        return MergeResult(value: value, conflicts: conflicts)
    }
}
