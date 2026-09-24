import SwiftUI

struct ItineraryView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editMode: EditMode = .inactive
    @State private var editingStop: Stop?
    @State private var replacingStop: Stop?
    @State private var photoSaver = PhotoSaveController()
    @State private var overview = false
    @State private var custom = false
    @State private var addingPlaces = false
    @State private var ticketPlace: Place?
    @State private var pendingRemoval: [Stop] = []
    @State private var confirmRemoval = false
    @State private var pendingMove: Stop?
    @State private var moveDay = 0
    @State private var confirmMove = false
    var body: some View {
        VStack(spacing: 0) {
            if typeSize.isAccessibilitySize {
                HStack {
                    Picker("日期", selection: Binding(get: { store.selectedDay }, set: { store.selectedDay = $0 })) {
                        ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, day in
                            Text(String(day.date.suffix(5))).tag(index)
                        }
                    }.pickerStyle(.menu).labelsHidden().fixedSize(horizontal: true, vertical: false).accessibilityLabel("行程日期")
                    Spacer()
                    Menu {
                        Button(overview ? "查看单日" : "\(store.plan.days.count) 日总览") { overview.toggle() }
                        Button(editMode.isEditing ? "完成排序" : "编辑排序") { editMode = editMode.isEditing ? .inactive : .active }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("行程操作")
                }.padding(.horizontal, 22)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("我们的行程").font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                    Spacer()
                    Button(overview ? "单日" : "总览", systemImage: overview ? "list.bullet" : "rectangle.split.3x1") { overview.toggle() }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).accessibilityLabel(overview ? "查看单日" : "\(store.plan.days.count) 日总览")
                    Button(editMode.isEditing ? "完成" : "编辑") { withAnimation(reduceMotion ? nil : .default) { editMode = editMode.isEditing ? .inactive : .active } }.font(.subheadline).frame(minHeight: 44)
                }.padding(.horizontal, 22).padding(.vertical, 14)
            }
            if overview {
                List {
                    ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, day in
                        Section {
                            ForEach(day.items) { item in
                                Button { store.selectedDay = index; overview = false } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(store.place(item.place)?.name ?? "自定义安排", systemImage: store.place(item.place)?.isDining == true ? "fork.knife" : "mappin")
                                        if let meal = item.meal { Text(MealPlan.label(meal.kind) + " · " + meal.reservation.label).font(.caption).foregroundStyle(TripStyle.green) }
                                        Text(item.scheduleLabel(fallbackHours: store.place(item.place)?.hours ?? 0)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }.foregroundStyle(.primary)
                            }
                        } header: { Text(day.date) }
                    }
                }.scrollContentBackground(.hidden)
            } else {
                if !typeSize.isAccessibilitySize { dayStrip }
                if store.selectedDay != store.todayIndex { Button("回到今天", systemImage: "arrow.uturn.backward") { store.selectedDay = store.todayIndex }.font(.caption).padding(.bottom, 4) }
                ScrollViewReader { proxy in
                List {
                    if store.currentDay.items.isEmpty {
                        ContentUnavailableView {
                            Label("这一天，留给喜欢的地方", systemImage: "calendar.badge.plus")
                        } description: {
                            Text("添加一个地点，慢慢安排当天的旅程。")
                        } actions: {
                            Button("添加地点", systemImage: "plus") { addingPlaces = true }.buttonStyle(.borderedProminent)
                        }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    }
                    Section {
                        ForEach(store.currentDay.items) { item in
                            if let place = store.place(item.place) {
                                NavigationLink { ScheduledPlaceDestination(item: item, place: place) } label: { StopRow(item: item, place: place) }
                                    .listRowBackground(TripStyle.card)
                                    .id(item.uid)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { remove(item) } label: { Label("移除", systemImage: "trash") }
                                        Button { editingStop = item } label: { Label("编辑", systemImage: "pencil") }.tint(TripStyle.green)
                                    }
                                    .accessibilityActions {
                                        if !place.isDining { Button("更换地点") { replacingStop = item } }
                                        if let path = store.album(place.id)?.photos.first?.path {
                                            Button("保存地点图片到相册") { photoSaver.save(path: path) }
                                        }
                                    }
                                    .contextMenu {
                                        if !place.isDining { Button("更换地点", systemImage: "mappin.and.ellipse") { replacingStop = item } }
                                        if let path = store.album(place.id)?.photos.first?.path {
                                            Button("保存地点图片到相册", systemImage: "square.and.arrow.down") { photoSaver.save(path: path) }.disabled(photoSaver.isSaving)
                                        }
                                        if !place.isDining { Button("打开地点票券", systemImage: "ticket") { ticketPlace = place } }
                                        Button("编辑时间与备注", systemImage: "pencil") { editingStop = item }
                                        Menu("移至其他日期", systemImage: "calendar") {
                                            ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, day in
                                                if index != store.selectedDay { Button(day.date) { requestMove(item, to: index) } }
                                            }
                                        }
                                        Button("移除安排", systemImage: "trash", role: .destructive) { remove(item) }
                                    }
                            }
                        }
                        .onMove { source, destination in _ = store.edit { $0.days[store.selectedDay].items.move(fromOffsets: source, toOffset: destination) } }
                        .onDelete { indices in requestRemoval(indices.map { store.currentDay.items[$0] }) }
                    } footer: {
                        if editMode.isEditing { Text("拖动可调整顺序，不会修改时间。新增安排或修改时间段后，会重新按时间排序。") }
                    }
                    if let tickets = store.plan.tickets {
                        let ids = Set(store.currentDay.items.map(\.place))
                        let places = store.allPlaces.filter { ids.contains($0.id) && !(tickets[$0.id] ?? []).isEmpty }
                        if !places.isEmpty {
                            Section("行程里的票券") {
                                ForEach(places) { place in
                                    Button { ticketPlace = place } label: { Label(place.name, systemImage: "ticket") }
                                }
                            }.listRowBackground(TripStyle.card)
                        }
                    }
                    Section {
                        Button { addingPlaces = true } label: { Label("为 \(TripConfig.shortDate(store.currentDay.date)) 添加地点", systemImage: "plus") }
                        NavigationLink { DiningSuggestionsView(day: store.selectedDay) } label: { Label("添加餐饮 · 看看顺路吃什么", systemImage: "fork.knife") }
                        Button("添加自定义安排", systemImage: "square.and.pencil") { custom = true }
                        if store.canUndo { Button("撤销上次修改", systemImage: "arrow.uturn.backward") { store.undo() } }
                    }.listRowBackground(TripStyle.card)
                    Section { DayRouteCard(day: store.currentDay, tab: 1) }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
                    Section {
                        DisclosureGroup("下雨时，这样调整") {
                            ForEach(store.currentDay.items) { item in
                                if let place = store.place(item.place), !place.rain.isEmpty { VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.subheadline.weight(.medium)); Text(place.rain).font(.footnote).foregroundStyle(.secondary) }.padding(.vertical, 5) }
                            }
                        }
                    }.listRowBackground(TripStyle.card)
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden).environment(\.editMode, $editMode)
                    .task(id: store.focusedStopID) {
                        guard let id = store.focusedStopID else { return }
                        await Task.yield()
                        proxy.scrollTo(id, anchor: .center)
                        store.focusedStopID = nil
                    }
                }
            }
        }.background(TripStyle.paper)
        .sensoryFeedback(.selection, trigger: store.selectedDay)
        .photoSaveFeedback(photoSaver)
        .sheet(item: $replacingStop) { item in NavigationStack { ReplacePlacePicker(item: item) } }
        .sheet(item: $editingStop) { item in NavigationStack {
            if let place = store.place(item.place), place.isDining { MealEditor(place: place, day: store.selectedDay, item: item) }
            else { StopEditor(item: item, suggestedHours: store.place(item.place)?.hours ?? 1) }
        } }
        .confirmationDialog("移除 App 中的用餐安排？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("移除安排", role: .destructive) { removeConfirmed(pendingRemoval) }
        } message: { Text("其中有已预订的餐食。这不会取消餐厅订单，请自行联系餐厅处理预约。") }
        .confirmationDialog("移动 App 中的用餐安排？", isPresented: $confirmMove, titleVisibility: .visible) {
            Button("移动行程，保留预约记录") { if let pendingMove { move(pendingMove, to: moveDay) } }
        } message: { Text("餐厅已确认的预约时间保持不变。移动后请联系餐厅确认是否能改期。") }
        .sheet(item: $ticketPlace) { place in NavigationStack { TicketListView(place: place).toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { ticketPlace = nil } } } } }
        .sheet(isPresented: $addingPlaces) { NavigationStack { ItineraryPlacePicker(day: store.selectedDay) } }
        .sheet(isPresented: $custom) { NavigationStack { CustomPlaceEditor() } }
    }
    private var dayStrip: some View {
        Group {
            if store.plan.days.count <= 7 {
                HStack(spacing: 8) { ForEach(store.plan.days.indices, id: \.self) { dayButton($0).frame(maxWidth: .infinity) } }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(store.plan.days.indices, id: \.self) { dayButton($0).frame(width: 52) } }
                }
            }
        }.padding(.horizontal, 22).padding(.bottom, 8)
    }
    private func dayButton(_ index: Int) -> some View {
        let parts = TripClock.date(store.plan.days[index].date).map { TripClock.calendar.dateComponents([.weekday, .month, .day], from: $0) }
        return Button { store.selectedDay = index } label: {
            VStack(spacing: 6) {
                Text(["周日","周一","周二","周三","周四","周五","周六"][((parts?.weekday ?? 1) - 1) % 7]).font(.caption2)
                Text("\(parts?.day ?? index + 1)").font(.system(.title3, design: .rounded, weight: .semibold))
                Circle().fill(index == store.selectedDay ? TripStyle.coral : .clear).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
            .foregroundStyle(index == store.selectedDay ? TripStyle.paper : TripStyle.green)
            .background(index == store.selectedDay ? TripStyle.green : TripStyle.card, in: .rect(cornerRadius: 18))
        }.buttonStyle(.plain).id(index).accessibilityLabel("\(parts?.month ?? 0) 月 \(parts?.day ?? 0) 日").accessibilityAddTraits(index == store.selectedDay ? .isSelected : [])
    }
    private func remove(_ item: Stop) { requestRemoval([item]) }
    private func requestRemoval(_ items: [Stop]) {
        if items.contains(where: { $0.meal?.reservation.status == "booked" }) { pendingRemoval = items; confirmRemoval = true }
        else { removeConfirmed(items) }
    }
    private func removeConfirmed(_ items: [Stop]) {
        let ids = Set(items.map(\.uid))
        _ = store.edit { plan in for day in plan.days.indices { plan.days[day].items.removeAll { ids.contains($0.uid) } } }
    }
    private func requestMove(_ item: Stop, to index: Int) {
        if item.meal?.reservation.status == "booked" { pendingMove = item; moveDay = index; confirmMove = true }
        else { move(item, to: index) }
    }
    private func move(_ item: Stop, to index: Int) {
        guard store.plan.days.contains(where: { $0.items.contains(where: { $0.uid == item.uid }) }) else {
            store.error = "这餐已被另一台设备移除，请查看最新行程。"; return
        }
        _ = store.editSchedule { plan in
            guard let current = plan.days.flatMap(\.items).first(where: { $0.uid == item.uid }) else { return }
            for day in plan.days.indices { plan.days[day].items.removeAll { $0.uid == item.uid } }
            plan.days[index].items.append(current)
        }
    }
}
struct StopRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TripStore.self) private var store
    var item: Stop
    var place: Place
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 13)) : AnyLayout(HStackLayout(alignment: .top, spacing: 13))) {
            VStack(spacing: 8) { Text(item.time.isEmpty ? "随心" : item.time).font(.caption.monospacedDigit().weight(.medium)); Circle().fill(TripStyle.coral).frame(width: 6, height: 6) }.frame(width: typeSize.isAccessibilitySize ? nil : 40).foregroundStyle(TripStyle.green).padding(.top, 4)
            VStack(alignment: .leading, spacing: 7) {
                Label(place.name, systemImage: place.isDining ? "fork.knife" : "mappin").font(.headline).foregroundStyle(TripStyle.green)
                Text(item.scheduleLabel(fallbackHours: place.hours)).font(.caption.monospacedDigit()).foregroundStyle(TripStyle.green)
                Text(place.en).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text(item.note.isEmpty ? place.desc : item.note).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                if let meal = item.meal {
                    Text(MealPlan.label(meal.kind) + " · " + meal.reservation.label).font(.caption).foregroundStyle(TripStyle.green)
                    if let day = store.plan.days.first(where: { $0.items.contains(where: { $0.uid == item.uid }) }), meal.reservation.differs(from: item, day: day.date) {
                        Label("行程与预约时间不同", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(TripStyle.coral)
                    }
                }
                if !place.isDining && !(store.plan.tickets?[place.id] ?? []).isEmpty { Label("已存门票", systemImage: "ticket").font(.caption2).foregroundStyle(TripStyle.coral) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
                if place.isDining { Image(systemName: "fork.knife.circle.fill").font(.system(size: 38)).foregroundStyle(TripStyle.green.opacity(0.6)).frame(width: 54) }
                else { LocalPhoto(path: store.album(place.id)?.thumb, height: 74, pixelSize: 300, originalPath: store.album(place.id)?.photos.first?.path, allowsPhotoSaving: false).frame(width: 70).clipShape(.rect(cornerRadius: 13)) }
            }
        }.padding(.vertical, 10)
    }
}
struct StopEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var item: Stop
    @State private var schedule: ScheduleDraft
    private let originalSchedule: ScheduleDraft
    init(item: Stop, suggestedHours: Double) {
        _item = State(initialValue: item)
        let draft = ScheduleDraft(item: item, suggestedHours: suggestedHours)
        _schedule = State(initialValue: draft)
        originalSchedule = draft
    }
    var body: some View {
        Form {
            ScheduleFields(draft: $schedule)
            Section("给我们的备注 · 选填") { PlanNoteInput(text: $item.note, placeholder: "例如：先吃午饭，再慢慢逛；下雨就改去室内。", minHeight: 160) }
        }.scrollDismissesKeyboard(.interactively).navigationTitle(store.place(item.place)?.name ?? "编辑安排").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                if schedule != originalSchedule { schedule.apply(to: &item) }
                if store.editSchedule({ plan in for d in plan.days.indices { if let i = plan.days[d].items.firstIndex(where: { $0.uid == item.uid }) { plan.days[d].items[i] = item } } }) { dismiss() }
            }.disabled(!schedule.isValid) }
        }.onAppear { store.editingForms += 1 }.onDisappear { store.editingForms -= 1 }
    }
}
