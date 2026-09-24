import SwiftUI
import MapKit

struct RouteEnglishAddressEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var node: RouteNode
    var onCopy: (String) -> Void
    @State private var name = ""
    @State private var address = ""
    @State private var query = ""
    @State private var results: [RouteLocation] = []
    @State private var preview: RouteLocation?
    @State private var searching = false
    @State private var message: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var generation = UUID()
    private let api = TripAPI()
    private var draft: RouteEnglishAddress { .init(name: name, address: address) }
    private var currentNode: RouteNode? {
        store.plan.days.flatMap { DayRoute(day: $0, plan: store.plan, content: store.content, preferences: store.routePreferences.state).nodes }
            .first { $0.id == node.id && $0.englishAddressKey == node.englishAddressKey }
    }
    var body: some View {
        Form {
            Section {
                Text(node.name).font(.headline)
                Text("核对英文名称、分店和地址后保存。资料会共享给其他设备，不会改变路线中的地图位置。").font(.footnote).foregroundStyle(.secondary)
                if !store.routePreferences.englishAddressSharing {
                    Label("所有设备更新完成并启用共享后，即可保存补全资料。", systemImage: "info.circle").font(.footnote)
                }
                Text(store.routePreferences.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("查找英文资料") {
                TextField("英文地点名或地址", text: $query).textInputAutocapitalization(.never).keyboardType(.asciiCapable).autocorrectionDisabled().submitLabel(.search).onSubmit { search() }
                Button("查找\(TripConfig.current.destination.name)地点", systemImage: "magnifyingglass") { search() }
                    .disabled(RouteEnglishAddress.clean(query).isEmpty)
                if searching { ProgressView("正在查找…") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                    Button {
                        name = item.name; address = item.address; preview = item; results = []
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name)
                            Text(item.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("核对英文地址") {
                TextField("英文地点名（含分店）", text: $name, axis: .vertical)
                    .textInputAutocapitalization(.words).keyboardType(.asciiCapable).autocorrectionDisabled().accessibilityIdentifier("route.address.name")
                TextField("街道、门牌或地标所在区域", text: $address, axis: .vertical)
                    .textContentType(.fullStreetAddress).keyboardType(.asciiCapable).autocorrectionDisabled().accessibilityIdentifier("route.address.address")
                Text("保留单元号和已有邮编，不确定的信息请勿填写。").font(.caption).foregroundStyle(.secondary)
                if let preview {
                    Map(initialPosition: .region(.init(center: preview.coordinate, span: .init(latitudeDelta: 0.006, longitudeDelta: 0.006)))) {
                        Marker(preview.name, coordinate: preview.coordinate)
                    }.frame(height: 200).id(preview)
                    Text("地图仅用于核对候选地点；手动编辑文字不会移动地图标记。").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let text = draft.copyText {
                Section("将复制以下内容") { Text(text).textSelection(.enabled) }
            } else {
                Text("请填写英文地点名和具体地址；仅国家或邮编不足以确认目的地。").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("保存并复制", systemImage: "doc.on.doc") {
                    guard currentNode != nil else { message = "这个地点或地图位置已变化，请关闭后重新打开。"; return }
                    guard let text = draft.copyText else { return }
                    let saved = RouteEnglishAddress(name: RouteEnglishAddress.clean(name), address: RouteEnglishAddress.withoutDestinationPrefix(address))
                    if store.routePreferences.set(node.englishAddressKey, .init(kind: "englishAddress", title: node.name + " · 英文地址", englishAddress: saved)) {
                        onCopy(text); dismiss()
                    }
                }.disabled(draft.copyText == nil || !store.routePreferences.englishAddressSharing || currentNode == nil)
                    .accessibilityIdentifier("route.address.save")
                if currentNode == nil { Text("这个地点或地图位置已变化，请关闭后重新打开。").foregroundStyle(TripStyle.coral) }
                if let error = store.routePreferences.error { Text(error).foregroundStyle(TripStyle.coral) }
            }
            Link("地点数据 © OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("核对英文地址").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .onAppear {
            let existing = node.englishAddress(in: store.routePreferences.state)
            name = existing?.name ?? ""; address = existing?.address ?? ""
            query = RouteEnglishAddress.isEnglish(name) ? name : node.query
            preview = node.location
        }
        .onDisappear { generation = UUID(); searchTask?.cancel() }
    }
    private func search() {
        guard !RouteEnglishAddress.clean(query).isEmpty else { return }
        searchTask?.cancel(); let token = UUID(); generation = token
        searching = true; results = []; message = nil
        searchTask = Task { @MainActor in
            do {
                let found = try await api.searchRoutePlaces(query)
                guard !Task.isCancelled, generation == token else { return }
                results = found
                if found.isEmpty { message = "没有找到可确认的地点，请换一个英文名称或地址重试。" }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                message = DayRouteService.failureMessage(error)
            }
            searching = false
        }
    }
}
