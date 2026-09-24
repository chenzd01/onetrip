import SwiftUI

struct CustomPlaceEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var replacing: Stop? = nil
    var onReplaced: (() -> Void)? = nil
    @State private var place = Place(id: UUID().uuidString.lowercased(), name: "", en: "", zone: "自定义", kind: "自定义", hours: 1, budget: 0, desc: "", tip: "", travel: "", rain: "", food: "", link: "")
    @State private var schedule = ScheduleDraft(isTimed: false)
    @State private var note = ""
    @State private var day = 0
    @State private var initializedDay = false
    @State private var isEditing = false
    @State private var showingMore = false
    @State private var replacementError: String?
    @FocusState private var keyboardFocused: Bool
    private var zones: [String] { Set(store.content.catalog.places.map(\.zone)).filter { !$0.isEmpty }.sorted() }
    var body: some View {
        Form {
            Section {
                TextField("例如：找一家咖啡馆", text: $place.name, axis: .vertical)
                    .lineLimit(2...4).focused($keyboardFocused).accessibilityLabel("安排名称，必填")
            } header: { Text("想做什么") } footer: { Text("只填名称就能添加，其余均为选填。") }
            if let replacing {
                Section("保留原安排") {
                    Text(replacing.scheduleLabel(fallbackHours: store.place(replacing.place)?.hours ?? 0))
                    Text("保留原日期、已设时间段、备注与顺序。新地点与更换安排会一起保存。").font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                Section("放在哪一天") {
                    Picker("日期", selection: $day) { ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, date in Text(date.date).tag(index) } }
                }
                ScheduleFields(draft: $schedule)
                Section("给我们的备注 · 选填") {
                    PlanNoteInput(text: $note)
                }
            }
            Section {
                DisclosureGroup("更多选填", isExpanded: $showingMore) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("英文名称或地址").font(.subheadline)
                        TextField("用于地图搜索", text: $place.en, axis: .vertical).lineLimit(2...4).focused($keyboardFocused)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("区域").font(.subheadline)
                            Spacer()
                            Menu("选择已有区域") { ForEach(zones, id: \.self) { zone in Button(zone) { place.zone = zone } } }
                        }
                        TextField("也可以自己填写", text: $place.zone, axis: .vertical).lineLimit(1...3).focused($keyboardFocused)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("一句说明").font(.subheadline)
                        TextField("例如：散步途中歇脚的小店", text: $place.desc, axis: .vertical).lineLimit(3...6).focused($keyboardFocused)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("每人预算 · " + TripConfig.current.currency.local).font(.subheadline)
                        TextField("0", value: $place.budget, format: .number).keyboardType(.decimalPad).focused($keyboardFocused).accessibilityLabel("每人预算，" + TripConfig.current.currency.local)
                        Text("默认 0，不增加预计支出；有估价后再填写。").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("交通说明").font(.subheadline)
                        TextField("例如：从地铁站步行约 5 分钟", text: $place.travel, axis: .vertical).lineLimit(3...6).focused($keyboardFocused)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("参考链接").font(.subheadline)
                        TextField("https://", text: $place.link, axis: .vertical).lineLimit(2...4).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($keyboardFocused)
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle(replacing == nil ? "自定义安排" : "新建并更换地点").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(replacing == nil ? "添加" : "新建并更换") {
                if let replacing {
                    if store.replacePlace(for: replacing, with: place, isNewCustom: true) {
                        if let onReplaced { onReplaced() } else { dismiss() }
                    } else { replacementError = store.error; store.error = nil }
                    return
                }
                var item = Stop(uid: UUID().uuidString.lowercased(), place: place.id, time: "", note: note)
                schedule.apply(to: &item)
                if store.editSchedule({ p in p.custom.append(place); p.days[day].items.append(item) }) { store.selectedDay = day; dismiss() }
            }.disabled(place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (replacing == nil && !schedule.isValid)) }
            ToolbarItemGroup(placement: .keyboard) {
                if keyboardFocused { Spacer(); Button("收起键盘") { keyboardFocused = false } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let replacementError {
                Label(replacementError, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(TripStyle.coral)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.regularMaterial)
            }
        }
        .onAppear {
            if !initializedDay { day = store.selectedDay; initializedDay = true }
            if !isEditing { store.editingForms += 1; isEditing = true }
        }.onDisappear {
            if isEditing { store.editingForms -= 1; isEditing = false }
        }
    }
}
