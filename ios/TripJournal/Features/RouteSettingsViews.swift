import SwiftUI
import MapKit

struct RouteHotelPicker: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var date: String
    private var stays: [Stay] {
        (store.plan.stays ?? []).sorted {
            let left = $0.checkIn <= date && $0.checkOut >= date
            let right = $1.checkIn <= date && $1.checkOut >= date
            return left != right ? left : $0.checkIn < $1.checkIn
        }
    }
    var body: some View {
        Form {
            Section {
                Text("选择当天从哪里出发、最后回哪里。酒店只连接路线，不会新增行程安排。").font(.subheadline)
                Label("选择后自动保存并共享", systemImage: "checkmark.icloud").font(.caption).foregroundStyle(.secondary)
                Text(store.routePreferences.status).font(.caption).foregroundStyle(.secondary)
            }
            hotelSection(start: true)
            hotelSection(start: false)
            if stays.isEmpty { Section { Text("还没有登记住宿，请先在今日或行囊页面管理住宿。").foregroundStyle(.secondary) } }
            if let error = store.routePreferences.error { Text(error).foregroundStyle(TripStyle.coral) }
        }.navigationTitle("路线设置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
    private func hotelSection(start: Bool) -> some View {
        let key = RoutePreferences.hotelKey(date, start: start)
        let selected = store.routePreferences.state.values[key]?.value
        return Section(start ? "从哪里出发" : "最后回哪里") {
            Button { store.routePreferences.set(key, nil) } label: {
                HStack { Text(start ? "从第一站开始" : "在最后一站结束"); Spacer(); if selected == nil { Image(systemName: "checkmark") } }.frame(minHeight: 44)
            }.accessibilityAddTraits(selected == nil ? .isSelected : [])
            ForEach(stays) { stay in
                Button {
                    store.routePreferences.set(key, .init(kind: start ? "startHotel" : "endHotel", title: String(date.suffix(5)) + (start ? " 出发 · " : " 返回 · ") + stay.name, value: stay.id))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(stay.name).foregroundStyle(.primary)
                            Text(stay.checkIn + " 至 " + stay.checkOut).font(.caption).foregroundStyle(.secondary)
                            if stay.checkIn <= date && stay.checkOut >= date { Text("当天相关住宿").font(.caption).foregroundStyle(TripStyle.green) }
                        }
                        Spacer(); if selected == stay.id { Image(systemName: "checkmark") }
                    }.frame(minHeight: 44)
                }.accessibilityAddTraits(selected == stay.id ? .isSelected : [])
            }
            if let selected, !stays.contains(where: { $0.id == selected }) { Text("原酒店已删除，请重新选择或取消此端点。").foregroundStyle(TripStyle.coral) }
        }
    }
}
struct RouteLocationPicker: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var node: RouteNode
    @State private var query = ""
    @State private var results: [RouteLocation] = []
    @State private var chosen: RouteLocation?
    @State private var message: String?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    private let api = TripAPI()
    @State private var generation = UUID()
    var body: some View {
        Form {
            Section {
                Text(node.name).font(.headline)
                Text("搜索后核对名称、地址和地图，再确认位置。路网中的地点可能位于建筑中心；请核对实际入口。此位置会共享给其他设备。").font(.footnote).foregroundStyle(.secondary)
                TextField("英文地点名或地址", text: $query).textInputAutocapitalization(.never).submitLabel(.search).onSubmit { runSearch() }
                Button("查找\(TripConfig.current.destination.name)地点", systemImage: "magnifyingglass") { runSearch() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if searching { ProgressView("正在查找…") }
            Link("地点数据 © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption)
            if let message { Text(message).foregroundStyle(.secondary) }
            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                Button {
                    chosen = item; results = []
                } label: {
                    VStack(alignment: .leading, spacing: 5) { Text(item.name); Text(item.address).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if let chosen {
                Section("确认这个位置") {
                    Text(chosen.name).font(.headline)
                    Text(chosen.address).font(.subheadline)
                    Text("可缩放地图，轻点实际入口调整标记。确认前请核对道路是否可通行。").font(.caption).foregroundStyle(.secondary)
                    MapReader { proxy in
                        Map(initialPosition: .region(.init(center: chosen.coordinate, span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)))) {
                            Marker(chosen.name, coordinate: chosen.coordinate)
                        }
                        .onTapGesture { point in
                            if let coordinate = proxy.convert(point, from: .local), DestinationMaps.contains(coordinate) {
                                self.chosen = RouteLocation(name: chosen.name, address: chosen.address, latitude: coordinate.latitude, longitude: coordinate.longitude)
                            }
                        }
                    }.frame(height: 240).id(chosen.name + chosen.address)
                    Text("标记位置：\(chosen.latitude.formatted(.number.precision(.fractionLength(5))))，\(chosen.longitude.formatted(.number.precision(.fractionLength(5))))")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("确认并共享位置", systemImage: "checkmark.circle") {
                        if store.routePreferences.set(node.locationKey, .init(kind: "location", title: node.name + " · 地图位置", location: chosen)) { dismiss() }
                    }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                }
            }
            if store.routePreferences.state.values[node.locationKey] != nil {
                Section { Button("恢复原有位置", role: .destructive) { if store.routePreferences.set(node.locationKey, nil) { dismiss() } } }
            }
            if let error = store.routePreferences.error { Text(error).foregroundStyle(TripStyle.coral) }
        }.navigationTitle("确认地图位置").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onAppear { query = node.query; chosen = node.location }
            .onDisappear { generation = UUID(); searchTask?.cancel() }
    }
    private func runSearch() {
        searchTask?.cancel(); let token = UUID(); generation = token
        searching = true; message = nil; results = []; chosen = nil
        searchTask = Task { @MainActor in
            do {
                let places = try await api.searchRoutePlaces(query)
                guard generation == token, !Task.isCancelled else { return }
                results = places
                if results.isEmpty { message = "没有找到可确认的\(TripConfig.current.destination.name)地点，请换一个英文名称或地址。" }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                message = DayRouteService.failureMessage(error)
            }
            searching = false
        }
    }
}
struct RouteConflictsView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [String: MergeChoice] = [:]
    var body: some View {
        List {
            Section { Text("不同设备修改了同一项路线设置。请选择要保留的内容，其他独立修改会自动合并，原有行程同步不受影响。").font(.subheadline) }
            ForEach(store.routePreferences.conflicts) { conflict in
                Section(conflict.title) {
                    choice(conflict, side: .local, title: "这部手机", setting: conflict.local)
                    choice(conflict, side: .remote, title: "共享设置", setting: conflict.remote)
                }
            }
        }.navigationTitle("核对路线设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("稍后处理") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存选择") {
                        store.routePreferences.resolve(choices)
                        if store.routePreferences.conflicts.isEmpty { dismiss() }
                    }.disabled(!store.routePreferences.conflicts.allSatisfy { choices[$0.id] != nil })
                }
            }
    }
    private func choice(_ conflict: RoutePreferenceConflict, side: MergeChoice, title: String, setting: RouteSetting?) -> some View {
        Button { choices[conflict.id] = side } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(setting?.readable ?? "移除此设置，使用默认值").font(.subheadline).foregroundStyle(.primary) }
                Spacer(); Image(systemName: choices[conflict.id] == side ? "checkmark.circle.fill" : "circle")
            }.padding(.vertical, 10)
        }
    }
}
