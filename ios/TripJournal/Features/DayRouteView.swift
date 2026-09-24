import SwiftUI
import MapKit

private struct RouteObservation: ViewModifier {
    @Environment(TripStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var consumer = UUID()
    var legs: [RouteLeg]
    var active: Bool
    private var signature: String { (active && phase == .active ? "active:" : "inactive:") + legs.map { $0.requestKey ?? "missing" }.joined(separator: "|") }
    func body(content: Content) -> some View {
        content.task(id: signature) {
            guard active, phase == .active else { store.routeService.release(consumer); return }
            store.routeService.observe(legs, consumer: consumer)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                store.routeService.tick()
            }
        }.onDisappear { store.routeService.release(consumer) }
    }
}
struct DayRouteCard: View {
    @Environment(TripStore.self) private var store
    var day: TripDay
    var tab: Int
    private var route: DayRoute { DayRoute(day: day, plan: store.plan, content: store.content, preferences: store.routePreferences.state) }
    var body: some View {
        if store.isShared { card } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("当天路线", systemImage: "map").font(.headline).foregroundStyle(TripStyle.green)
                Text("路线计算与路线设置共享需要自建后端（见 docs/zh/backend.md）。").font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(TripStyle.card, in: .rect(cornerRadius: 22))
        }
    }
    private var card: some View {
        NavigationLink { DayRouteView(date: day.date) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("当天路线", systemImage: "map").font(.headline)
                    Spacer()
                    Text("展开地图").font(.subheadline)
                    Image(systemName: "arrow.up.right")
                }.foregroundStyle(TripStyle.green)
                Text("按时间，把今天串起来").font(.subheadline).foregroundStyle(.secondary)
                RouteMap(route: route, interactive: false, focusToken: .constant(0), selection: .constant(nil))
                    .frame(height: 220).clipShape(.rect(cornerRadius: 18)).allowsHitTesting(false).accessibilityHidden(true)
                RouteSummary(route: route)
                if !route.flexible.isEmpty { Text("另有 \(route.flexible.count) 项时间待定，设定时间后加入路线").font(.caption).foregroundStyle(.secondary) }
            }.padding(18).background(TripStyle.card, in: .rect(cornerRadius: 22))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("route.card")
            .modifier(RouteObservation(legs: route.legs, active: store.activeTab == tab))
    }
}
private struct RouteSummary: View {
    @Environment(TripStore.self) private var store
    var route: DayRoute
    private var results: [RouteResult] { route.legs.compactMap { store.routeService.result(for: $0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if route.nodes.isEmpty { Text("先给地点安排时间，再看看怎么走").font(.subheadline) }
            else if route.nodes.count == 1 { Text("已安排 1 站 · 再加一站即可生成路线").font(.subheadline) }
            else {
                Text("\(route.nodes.count) 站 · 已计算 \(results.count)/\(route.legs.count) 段").font(.subheadline.weight(.semibold))
                if !results.isEmpty {
                    Text((results.count == route.legs.count ? "全天路途 " : "已计算部分 ") + DayRouteService.distance(results.reduce(0) { $0 + $1.distance }) + " · 约 " + DayRouteService.duration(results.reduce(0) { $0 + $1.seconds }))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(TripStyle.green)
                    if let oldest = results.map(\.calculatedAt).min() {
                        Text("计算于 \(oldest.formatted(date: .omitted, time: .shortened)) · 不含游玩与等车").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if route.legs.contains(where: { $0.requestKey.map { store.routeService.loading.contains($0) } ?? false }) {
                    Label("正在更新路线…", systemImage: "arrow.trianglehead.2.clockwise").font(.caption).foregroundStyle(.secondary)
                } else if route.legs.contains(where: { $0.requestKey.map { store.routeService.failures[$0] != nil } ?? false }) {
                    Text(results.isEmpty ? "部分路段未能生成，请查看路段提示" : "部分路段更新失败，已有结果为上次估算").font(.caption).foregroundStyle(TripStyle.coral)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) { legend }
                VStack(alignment: .leading, spacing: 8) { legend }
            }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var legend: some View {
        Label("步行", systemImage: "figure.walk").foregroundStyle(TripStyle.green)
        Label("打车 · 驾车估算", systemImage: "car.fill").foregroundStyle(TripStyle.coral)
    }
}
private struct RouteMap: View {
    @Environment(TripStore.self) private var store
    var route: DayRoute
    var interactive: Bool
    var resetToken = 0
    @Binding var focusToken: Int
    @Binding var selection: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var userMovedCamera = false
    private var boundsID: String { route.nodes.map { $0.id + String($0.location?.latitude ?? 0) + String($0.location?.longitude ?? 0) }.joined() }
    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(route.legs) { leg in
                if let result = store.routeService.result(for: leg) {
                    MapPolyline(result.polyline)
                        .stroke(leg.driving ? TripStyle.coral : TripStyle.green, style: StrokeStyle(lineWidth: selection == leg.id ? 6 : 3, lineCap: .round, dash: leg.driving ? [8, 5] : []))
                }
            }
            ForEach(RouteMapGroup.groups(for: route.nodes)) { group in
                Annotation(group.location.name, coordinate: group.location.coordinate, anchor: .center) {
                    if group.stops.count == 1, let stop = group.stops.first {
                        Button { select(stop.id) } label: { marker(group) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("第 \(stop.number) 站，\(stop.node.time)，\(stop.node.name)")
                            .accessibilityHint("在地图和路线列表中查看此站")
                            .accessibilityAddTraits(selection == stop.id ? .isSelected : [])
                            .accessibilityIdentifier("route.marker." + stop.id)
                    } else {
                        Menu {
                            ForEach(group.stops) { stop in
                                Button { select(stop.id) } label: {
                                    if selection == stop.id { Label("第 \(stop.number) 站 · \(stop.node.time) · \(stop.node.name)", systemImage: "checkmark") }
                                    else { Text("第 \(stop.number) 站 · \(stop.node.time) · \(stop.node.name)") }
                                }
                            }
                        } label: { marker(group) }
                            .accessibilityLabel("同一位置有 \(group.stops.count) 站：" + group.stops.map { "第 \($0.number) 站，\($0.node.time)，\($0.node.name)" }.joined(separator: "；"))
                            .accessibilityHint("打开菜单选择要查看的站点")
                            .accessibilityIdentifier("route.markerGroup." + group.id)
                    }
                }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onChange(of: position.positionedByUser) { _, moved in if moved { userMovedCamera = true } }
        .onChange(of: resetToken) { _, _ in userMovedCamera = false; fitAll() }
        .onChange(of: boundsID, initial: true) { _, _ in if !userMovedCamera && selection == nil { fitAll() } }
        .onChange(of: focusToken) { _, _ in focusSelection() }
        .onChange(of: route.legs.compactMap { store.routeService.result(for: $0)?.calculatedAt }) { _, _ in
            if !userMovedCamera && selection == nil { fitAll() }
        }
    }
    private func marker(_ group: RouteMapGroup) -> some View {
        let selected = group.stops.contains { $0.id == selection }
        // Fixed dark fills keep white numerals legible in both map appearances.
        return Text(group.label).font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, group.stops.count > 1 ? 9 : 0)
            .frame(minWidth: selected ? 32 : 28, minHeight: selected ? 32 : 28)
            .background(selected ? Color(red: 0.58, green: 0.23, blue: 0.14) : Color(red: 0.16, green: 0.31, blue: 0.26), in: .capsule)
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .padding(selected ? 4 : 6)
            .overlay(Capsule().stroke(selected ? Color.primary : .clear, lineWidth: 1.5))
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
    private func select(_ id: String) {
        selection = id
        focusToken += 1
    }
    private func focusSelection() {
        if let node = route.nodes.first(where: { $0.id == selection }), let location = node.location {
            position = .region(.init(center: location.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))
        } else if let leg = route.legs.first(where: { $0.id == selection }), let result = store.routeService.result(for: leg) {
            position = .rect(padded(result.polyline.boundingMapRect))
        }
    }
    private func padded(_ rect: MKMapRect) -> MKMapRect {
        rect.insetBy(dx: -max(rect.width * 0.18, 1500), dy: -max(rect.height * 0.22, 1500))
    }
    private func fitAll() {
        var rect = MKMapRect.null
        for node in route.nodes { if let location = node.location { let point = MKMapPoint(location.coordinate); rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1)) } }
        for leg in route.legs { if let result = store.routeService.result(for: leg) { rect = rect.union(result.polyline.boundingMapRect) } }
        position = rect.isNull ? .region(DestinationMaps.region) : .rect(padded(rect))
    }
}
struct DayRouteView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: String?
    @State private var expanded = false
    @State private var resetToken = 0
    @State private var focusToken = 0
    @State private var sheet: RouteSheet?
    @State private var copyNotice: UUID?
    var date: String
    private var day: TripDay { store.plan.days.first { $0.date == date } ?? store.currentDay }
    private var route: DayRoute { DayRoute(day: day, plan: store.plan, content: store.content, preferences: store.routePreferences.state) }
    private enum RouteSheet: Identifiable {
        case hotels, conflicts, location(RouteNode), englishAddress(RouteNode), edit(Stop), replace(Stop)
        var id: String {
            switch self { case .hotels: "hotels"; case .conflicts: "conflicts"; case .location(let n): n.id; case .englishAddress(let n): "address:" + n.id; case .edit(let s): "edit:" + s.uid; case .replace(let s): "replace:" + s.uid }
        }
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                RouteMap(route: route, interactive: true, resetToken: resetToken, focusToken: $focusToken, selection: $selection)
                    .frame(height: max(160, geometry.size.height * (expanded || typeSize.isAccessibilitySize ? 0.28 : 0.43)))
                    .overlay(alignment: .bottomTrailing) {
                        Button { selection = nil; resetToken += 1 } label: {
                            Image(systemName: "viewfinder")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 44, height: 44)
                        }.accessibilityLabel("显示全天路线")
                            .buttonStyle(.glass).buttonBorderShape(.circle)
                            .padding(12).accessibilityIdentifier("route.fitAll")
                    }
                HStack {
                    Text(date.suffix(5) + " · 当天路线").font(.headline)
                    Spacer()
                    if !typeSize.isAccessibilitySize {
                        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: { Label(expanded ? "更多地图" : "更多路段", systemImage: expanded ? "chevron.down" : "chevron.up").font(.caption).frame(minHeight: 44) }
                            .accessibilityHint("调整地图与路线列表的显示比例")
                    }
                }.padding(.horizontal, 18).background(TripStyle.card)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            RouteSummary(route: route)
                            routeSettings
                            Text("按时间出发").font(.headline).accessibilityAddTraits(.isHeader)
                            ForEach(route.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(TripStyle.coral) }
                            ForEach(Array(route.nodes.enumerated()), id: \.element.id) { index, node in
                                nodeRow(node, number: index + 1).id(node.id)
                                if index < route.legs.count { legRow(route.legs[index]).id(route.legs[index].id) }
                            }
                            if !route.flexible.isEmpty {
                                Text("时间待定 · 暂未连入路线").font(.headline).padding(.top, 8)
                                ForEach(route.flexible) { stop in
                                    Button { sheet = .edit(stop) } label: {
                                        HStack { Text(store.place(stop.place)?.name ?? "自定义安排"); Spacer(); Label("安排时间", systemImage: "clock") }.font(.subheadline).frame(minHeight: 44)
                                    }
                                }
                            }
                            Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                                .font(.caption).frame(minHeight: 44)
                            Text("道路由 Valhalla 根据 OpenStreetMap 路网计算。打车为驾车估算，不含实时拥堵、叫车、等车和游玩时间；以出发时导航为准。")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(18)
                    }.background(TripStyle.paper)
                    .onChange(of: focusToken) { _, _ in
                        if let selection { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(selection, anchor: .top) } }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if copyNotice != nil {
                Label("英文地址已复制", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).padding(12).background(.regularMaterial, in: .capsule)
                    .padding(.top, 8).allowsHitTesting(false)
            }
        }
        .task(id: copyNotice) {
            guard copyNotice != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copyNotice = nil
        }
        .navigationTitle("当天路线").navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("刷新路线", systemImage: "arrow.clockwise") { store.routeService.refresh(route.legs) }
                    if !store.routePreferences.conflicts.isEmpty { Button("处理共享冲突", systemImage: "person.2") { sheet = .conflicts } }
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("路线操作")
            }
        }
        .modifier(RouteObservation(legs: route.legs, active: true))
        .onChange(of: route.nodes) { _, nodes in
            guard let selection else { return }
            if let node = nodes.first(where: { $0.id == selection }) {
                if node.location == nil { self.selection = nil }
            } else if !route.legs.contains(where: { $0.id == selection && $0.requestKey != nil }) {
                self.selection = nil
            }
        }
        .sheet(item: $sheet) { target in
            NavigationStack {
                switch target {
                case .hotels: RouteHotelPicker(date: date)
                case .conflicts: RouteConflictsView()
                case .location(let node): RouteLocationPicker(node: node)
                case .englishAddress(let node): RouteEnglishAddressEditor(node: node, onCopy: copyAddress)
                case .edit(let item):
                    if let place = store.place(item.place), place.isDining { MealEditor(place: place, day: store.plan.days.firstIndex { $0.date == date } ?? 0, item: item) }
                    else { StopEditor(item: item, suggestedHours: store.place(item.place)?.hours ?? 1) }
                case .replace(let item): ReplacePlacePicker(item: item)
                }
            }
        }
        .alert("路线设置未保存", isPresented: Binding(get: { store.routePreferences.error != nil }, set: { if !$0 { store.routePreferences.error = nil } })) {
            Button("知道了") { store.routePreferences.error = nil }
        } message: { Text(store.routePreferences.error ?? "") }
    }
    private var routeSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { sheet = .hotels } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(TripStyle.green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("路线设置").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text("出发：" + hotelName(start: true) + "\n返回：" + hotelName(start: false))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("route.settings")
            Divider()
            Label("设置自动保存并共享", systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
            if store.routePreferences.conflicts.isEmpty {
                Text(store.routePreferences.status).font(.caption).foregroundStyle(.secondary)
            } else {
                Button { sheet = .conflicts } label: {
                    Label("需要核对共享设置", systemImage: "exclamationmark.bubble").font(.subheadline).frame(minHeight: 44)
                }
                Text(store.routePreferences.status).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(TripStyle.card, in: .rect(cornerRadius: 16))
    }
    private func copyAddress(_ text: String) {
        UIPasteboard.general.string = text
        copyNotice = UUID()
        UIAccessibility.post(notification: .announcement, argument: "英文地址已复制")
    }
    private func hotelName(start: Bool) -> String {
        guard let id = store.routePreferences.state.values[RoutePreferences.hotelKey(date, start: start)]?.value else {
            return start ? "从第一站开始" : "在最后一站结束"
        }
        return store.plan.stays?.first(where: { $0.id == id })?.name ?? "酒店已删除，请重新选择"
    }
    private func select(_ id: String) {
        selection = id
        focusToken += 1
    }
    private func nodeRow(_ node: RouteNode, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Button {
                    if node.location == nil { sheet = .location(node) }
                    else { select(node.id) }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(number)").font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(TripStyle.green).frame(width: 28, height: 28)
                            .background(TripStyle.green.opacity(0.12), in: .circle)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(node.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(node.name).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: selection == node.id ? "scope" : "mappin").font(.subheadline).foregroundStyle(TripStyle.green)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("第 \(number) 站，\(node.time)，\(node.name)")
                    .accessibilityHint(node.location == nil ? "地图位置待确认" : "在地图中查看此站")
                    .accessibilityAddTraits(selection == node.id ? .isSelected : [])
                Menu {
                    if let stopID = node.stopID, let item = day.items.first(where: { $0.uid == stopID }) {
                        Button("编辑时间", systemImage: "clock") { sheet = .edit(item) }
                        if store.place(item.place)?.isDining != true {
                            Button("更换地点", systemImage: "arrow.triangle.2.circlepath") { sheet = .replace(item) }
                        }
                    }
                    Button("复制英文地址", systemImage: "doc.on.doc") {
                        if let text = node.englishAddress(in: store.routePreferences.state)?.copyText { copyAddress(text) }
                        else { sheet = .englishAddress(node) }
                    }
                    Button("核对英文地址", systemImage: "pencil") { sheet = .englishAddress(node) }
                    Button(node.location == nil ? "确认地图位置" : "核对位置", systemImage: "mappin") { sheet = .location(node) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel(node.name + "的更多操作")
            }
            if node.location == nil {
                Button("确认地图位置", systemImage: "mappin.and.ellipse") { sheet = .location(node) }
                    .font(.subheadline).frame(minHeight: 44).padding(.leading, 40)
            }
        }.padding(14).background(TripStyle.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selection == node.id ? TripStyle.green : .clear, lineWidth: 2))
    }
    private func legRow(_ leg: RouteLeg) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Rectangle().fill(TripStyle.green.opacity(0.25)).frame(width: 2, height: 12)
                Image(systemName: leg.driving ? "car.fill" : "figure.walk").font(.caption)
                    .foregroundStyle(TripStyle.green).frame(width: 28, height: 28)
                Rectangle().fill(TripStyle.green.opacity(0.25)).frame(width: 2)
            }.frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Button { select(leg.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(leg.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        Text(store.routeService.message(for: leg)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(leg.requestKey == nil).accessibilityHint("在地图中查看这段路线")
                    .accessibilityAddTraits(selection == leg.id ? .isSelected : [])
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { modePicker(leg); Spacer(minLength: 0); navigationButton(leg) }
                    VStack(alignment: .leading, spacing: 4) { modePicker(leg); navigationButton(leg) }
                }
                if leg.driving { Text("打车按驾车估算，不含叫车与等车").font(.caption).foregroundStyle(.secondary) }
                if let key = leg.requestKey, store.routeService.failures[key] != nil {
                    Button("重试这段路线", systemImage: "arrow.clockwise") { store.routeService.refresh([leg]) }.font(.subheadline).frame(minHeight: 44)
                }
            }.padding(12).background(selection == leg.id ? TripStyle.green.opacity(0.07) : .clear, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selection == leg.id ? TripStyle.green : .clear, lineWidth: 1))
        }.padding(.leading, 14).fixedSize(horizontal: false, vertical: true)
    }
    private func modePicker(_ leg: RouteLeg) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("交通方式").font(.caption).foregroundStyle(.secondary)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) { modeButton(leg, driving: false); modeButton(leg, driving: true) }
            } else {
                HStack(spacing: 6) { modeButton(leg, driving: false); modeButton(leg, driving: true) }
            }
        }
    }
    private func modeButton(_ leg: RouteLeg, driving: Bool) -> some View {
        let selected = leg.driving == driving
        return Button {
            store.routePreferences.set(leg.id, .init(kind: "mode", title: leg.title, value: driving ? "driving" : "walking"))
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark" : (driving ? "car.fill" : "figure.walk"))
                Text(driving ? "打车" : "步行").fixedSize(horizontal: true, vertical: false)
            }.font(.subheadline).padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : TripStyle.green)
                .background(selected ? TripStyle.green : TripStyle.green.opacity(0.07), in: .rect(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(leg.title + (driving ? "，打车" : "，步行"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint("更改后自动保存并重新计算这一段")
    }
    private func navigationButton(_ leg: RouteLeg) -> some View {
        Button("导航这段", systemImage: "arrow.triangle.turn.up.right.diamond") { navigate(leg) }
            .font(.subheadline).fixedSize(horizontal: true, vertical: false)
            .disabled(leg.requestKey == nil).frame(minHeight: 44)
            .accessibilityHint("打开 Apple 地图，导航这一段路线")
    }
    private func navigate(_ leg: RouteLeg) {
        guard let a = leg.from.location, let b = leg.to.location,
              let start = DestinationMaps.item(name: a.name, address: a.address, coordinates: [a.latitude, a.longitude]),
              let end = DestinationMaps.item(name: b.name, address: b.address, coordinates: [b.latitude, b.longitude]) else { return }
        if !MKMapItem.openMaps(with: [start, end], launchOptions: [MKLaunchOptionsDirectionsModeKey: leg.driving ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking]) {
            store.error = "暂时无法打开 Apple 地图，请检查是否已安装地图 App。"
        }
    }
}
