import Foundation

/// Translates merge paths into the same names people see in their travel plan.
struct ConflictPresentation {
    struct Row: Identifiable {
        var id: String
        var title: String
        var local: String
        var remote: String
        var changed: Bool { local != remote }
    }
    let content: ContentCatalog
    let plans: [TripPlan]
    private static let local = TripConfig.current.currency.local, home = TripConfig.current.currency.home
    private static let labels = [
        "meal": "用餐安排", "reservation": "餐厅预约", "partySize": "用餐人数",
        "行程": "行程", "整份行程": "整份行程", "days": "每日安排", "items": "景点安排",
        "custom": "自定义地点", "checks": "出行准备", "budget": "预算", "hotelFavorites": "收藏酒店",
        "stays": "住宿", "tickets": "票据", "title": "标题", "name": "名称", "date": "日期",
        "time": "时间", "note": "备注", "notes": "备注", "area": "区域", "place": "地点",
        "hotel": "住宿预算（\(local)）", "food": "餐饮预算（\(local)）", "transport": "交通预算（\(local)）",
        "flightOut": "去程机票（\(home)）", "flightReturn": "返程机票（\(home)）", "other": "其他费用（\(local)）", "address": "地址",
        "phone": "电话", "checkIn": "入住日期", "checkOut": "退房日期", "checkInTime": "入住时间",
        "checkOutTime": "退房时间", "lateArrival": "晚到", "status": "状态", "quantity": "数量",
        "provider": "预订平台", "reference": "预订编号", "url": "链接", "deadline": "截止时间",
        "files": "附件", "type": "文件类型", "size": "文件大小（字节）", "en": "英文名", "zone": "区域",
        "kind": "类型", "hours": "游览时长（小时）", "desc": "介绍", "tip": "提示", "travel": "交通方式",
        "rain": "雨天安排", "link": "来源链接", "opening": "营业时间", "price": "价格", "bestTime": "推荐时段",
        "排序": "顺序", "version": "数据版本"
    ]
    func name(_ key: String) -> String {
        if let label = Self.labels[key] { return label }
        if let preparation = content.preparation.first(where: { $0.id == key }) { return preparation.title }
        if let hotel = content.hotels.hotels.first(where: { $0.id == key }) { return hotel.name }
        for plan in plans {
            if let place = (plan.custom + content.catalog.places).first(where: { $0.id == key }) { return place.name }
            for day in plan.days {
                if day.date == key { return "\(day.date) · \(day.title)" }
                if let stop = day.items.first(where: { $0.uid == key }) { return name(stop.place) }
            }
            if let stay = plan.stays?.first(where: { $0.id == key }) { return stay.name.isEmpty ? "住宿安排" : stay.name }
            if let ticket = plan.tickets?.values.flatMap({ $0 }).first(where: { $0.id == key }) { return ticket.title.isEmpty ? "票据" : ticket.title }
            if let file = plan.tickets?.values.flatMap({ $0 }).flatMap(\.files).first(where: { $0.id == key }) { return file.name }
        }
        return key
    }
    func title(_ conflict: MergeConflict) -> String {
        let parts = conflict.path.split(separator: "/").map(String.init)
        if parts.count == 1 { return name(parts[0]) }
        return parts.filter { !["行程", "days", "items"].contains($0) }.map { key in
            if plans.contains(where: { $0.days.contains(where: { $0.date == key }) }) { return key }
            return name(key)
        }.joined(separator: " · ")
    }
    func rows(_ conflict: MergeConflict) -> [Row] {
        func flatten(_ value: JSONValue?, path: String, label: String) -> [String: (String, String)] {
            guard let value else { return [path: (label, "已删除")] }
            switch value {
            case .object(let object):
                var output: [String: (String, String)] = [:]
                for key in object.keys.sorted() where !["id", "uid"].contains(key) {
                    let field = label.isEmpty ? name(key) : label + " · " + name(key)
                    output.merge(flatten(object[key], path: path + "/" + key, label: field)) { _, new in new }
                }
                return output.isEmpty ? [path: (label, "未填写")] : output
            case .array(let values):
                if values.isEmpty { return [path: (label, "无内容")] }
                var output: [String: (String, String)] = [:]
                for (index, child) in values.enumerated() {
                    output.merge(flatten(child, path: path + "/\(index)", label: label + " · 第\(index + 1)项")) { _, new in new }
                }
                return output
            case .string(let value):
                let fullPath = conflict.path + path
                let field = String(fullPath.split(separator: "/").last ?? "")
                let statuses = ["planned": "待预订", "booked": "已预订", "used": "已使用", "cancelled": "已取消", "notRequired": "无需预约"]
                let text: String
                if field == "status" { text = statuses[value] ?? value }
                else if field == "kind" && fullPath.contains("/meal") { text = MealPlan.label(value) }
                else if field == "place" || fullPath.contains("/排序/") || fullPath.contains("/hotelFavorites/") { text = name(value) }
                else { text = value }
                return [path: (label, text.isEmpty ? "未填写" : text)]
            case .number(let value): return [path: (label, value.formatted(.number.precision(.fractionLength(0...2))))]
            case .bool(let value): return [path: (label, value ? "是 / 已勾选" : "否 / 未勾选")]
            case .null: return [path: (label, "未填写")]
            }
        }
        let label = name(String(conflict.path.split(separator: "/").last ?? "内容"))
        let local = flatten(conflict.local, path: "", label: label)
        let remote = flatten(conflict.remote, path: "", label: label)
        return Set(local.keys).union(remote.keys).sorted().map { key in
            Row(id: key, title: local[key]?.0 ?? remote[key]?.0 ?? label,
                local: local[key]?.1 ?? (conflict.local == nil ? "已删除" : "无此内容"),
                remote: remote[key]?.1 ?? (conflict.remote == nil ? "已删除" : "无此内容"))
        }
    }
}
