import Foundation

enum StopReplacement {
    static func applying(to plan: TripPlan, catalog: [Place], item: Stop, destination: Place, isNewCustom: Bool = false) throws -> TripPlan {
        guard let day = plan.days.firstIndex(where: { $0.items.contains { $0.uid == item.uid } }),
              let index = plan.days[day].items.firstIndex(where: { $0.uid == item.uid }) else {
            throw TripError.message("这条安排已被移除，请返回行程重新选择。")
        }
        let current = plan.days[day].items[index]
        guard current.place == item.place else {
            throw TripError.message("这条安排的地点已更新，请返回行程重新选择。")
        }
        let places = catalog + plan.custom
        guard let original = places.first(where: { $0.id == current.place }) else {
            throw TripError.message("原地点已不存在，请返回行程检查。")
        }
        guard !original.isDining, !destination.isDining else {
            throw TripError.message("用餐安排请从餐饮编辑入口调整，原预约记录会继续保留。")
        }
        if isNewCustom {
            guard !places.contains(where: { $0.id == destination.id }), !destination.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TripError.message("请检查新地点的名称与编号。")
            }
        } else if !places.contains(where: { $0.id == destination.id }) {
            throw TripError.message("所选地点已不存在，请重新选择。")
        }
        var result = plan
        if isNewCustom { result.custom.append(destination) }
        var replacement = current
        replacement.place = destination.id
        if destination.id != current.place, replacement.durationMinutes == nil, !replacement.time.isEmpty {
            let duration = current.duration(fallbackHours: original.hours)
            guard (1...1440).contains(duration) else {
                throw TripError.message("原安排还没有有效停留时长，请先编辑时间段，再更换地点。")
            }
            replacement.durationMinutes = duration
        }
        result.days[day].items[index] = replacement
        return result
    }
}

extension TripStore {
    @discardableResult func replacePlace(for item: Stop, with destination: Place, isNewCustom: Bool = false) -> Bool {
        do {
            let next = try StopReplacement.applying(to: plan, catalog: content.catalog.places, item: item, destination: destination, isNewCustom: isNewCustom)
            try PlanValidation.validate(next, catalog: content)
            let saved = edit { $0 = next }
            if !saved && !hasConflicts {
                error = "未能保存更换，原安排已保留。请检查设备剩余空间后重试。"
            }
            return saved
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}
