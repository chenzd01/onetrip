import SwiftUI

struct MealEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let place: Place
    private let original: Stop?
    private let originalSchedule: ScheduleDraft
    var onAdded: (() -> Void)?
    @State private var day: Int
    @State private var item: Stop
    @State private var meal: MealPlan
    @State private var schedule: ScheduleDraft
    @State private var confirmChange = false

    init(place: Place, day: Int, item: Stop? = nil, kind: String = "lunch", onAdded: (() -> Void)? = nil) {
        self.place = place; original = item; self.onAdded = onAdded
        _day = State(initialValue: day)
        _item = State(initialValue: item ?? Stop(uid: UUID().uuidString.lowercased(), place: place.id, time: "", note: ""))
        _meal = State(initialValue: item?.meal ?? MealPlan(kind: kind))
        let draft = ScheduleDraft(item: item, suggestedHours: place.hours, isTimed: false)
        originalSchedule = draft
        _schedule = State(initialValue: draft)
    }
    private var candidate: Stop {
        var value = item
        if original == nil || schedule != originalSchedule { schedule.apply(to: &value) }
        value.meal = meal
        return value
    }
    private var warnings: [String] {
        DiningSchedule.warnings(item: candidate, day: store.plan.days[day], places: store.allPlaces, venue: store.content.dining?.venue(place.id))
    }
    private var reservationValid: Bool {
        meal.reservation.status != "booked" || (!meal.reservation.date.isEmpty && !meal.reservation.time.isEmpty)
    }
    var body: some View {
        Form {
            Section {
                Text(place.name).font(.headline).foregroundStyle(TripStyle.green)
                Picker("日期", selection: $day) {
                    ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, date in Text(date.date).tag(index) }
                }
                Picker("哪一餐", selection: $meal.kind) {
                    ForEach(MealPlan.kinds, id: \.self) { Text(MealPlan.label($0)).tag($0) }
                }
            }
            ScheduleFields(draft: $schedule)
            if !warnings.isEmpty {
                Section("安排前核对") {
                    ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(TripStyle.coral) }
                }
            }
            MealReservationFields(reservation: $meal.reservation, days: store.plan.days)
            if meal.reservation.status == "booked", !meal.reservation.date.isEmpty, !meal.reservation.time.isEmpty {
                Section {
                    Button("按预约时间安排这一餐", systemImage: "calendar.badge.clock") {
                        if let index = store.plan.days.firstIndex(where: { $0.date == meal.reservation.date }) { day = index }
                        var value = item; value.time = meal.reservation.time
                        value.durationMinutes = max(1, Int(place.hours * 60))
                        schedule = ScheduleDraft(item: value, suggestedHours: place.hours)
                    }
                }
            }
            Section("给我们的备注") { PlanNoteInput(text: $item.note) }
            Section {
                Text("餐厅价格仅供参考，不会自动修改旅行预算。加入行程不代表已经订位。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(original == nil ? "安排这一餐" : "编辑用餐").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(original == nil ? "加入行程" : "保存") {
                    if original?.meal?.reservation.status == "booked" && (original?.time != candidate.time || store.plan.days.first(where: { $0.items.contains(where: { $0.uid == item.uid }) })?.date != store.plan.days[day].date || original?.meal?.reservation != meal.reservation) {
                        confirmChange = true
                    } else { save() }
                }.disabled(!schedule.isValid || !reservationValid)
            }
        }
        .confirmationDialog("只更新 App 中的记录", isPresented: $confirmChange, titleVisibility: .visible) {
            Button("保存记录") { save() }
        } message: { Text("这不会改期或取消餐厅订单。请确认已与餐厅核对真实预约。") }
        .onAppear {
            store.editingForms += 1
            if original?.meal == nil, store.content.dining?.venue(place.id)?.isRestaurant == false { meal.reservation.status = "notRequired" }
        }
        .onDisappear { store.editingForms -= 1 }
    }
    private func save() {
        let value = candidate
        if store.editSchedule({ plan in
            DiningSchedule.apply(value, to: &plan, day: day)
        }) {
            store.selectedDay = day
            if original == nil { store.focusedStopID = value.uid; store.activeTab = 1 }
            if let onAdded { onAdded() } else { dismiss() }
        }
    }
}

private struct MealReservationFields: View {
    @Binding var reservation: DiningReservation
    let days: [TripDay]
    private var reservationTime: Binding<Date> {
        Binding(get: { TripClock.date("2001-01-01T" + reservation.time) ?? TripClock.date("2001-01-01T12:00")! }, set: {
            let parts = TripClock.calendar.dateComponents([.hour, .minute], from: $0)
            reservation.time = String(format: "%02d:%02d", parts.hour ?? 12, parts.minute ?? 0)
        })
    }
    var body: some View {
        Section {
            Picker("预约状态", selection: $reservation.status) {
                ForEach(DiningReservation.statuses, id: \.self) { status in Text(DiningReservation(status: status).label).tag(status) }
            }
            Stepper("用餐人数：\(reservation.partySize) 人", value: $reservation.partySize, in: 1...20)
            if reservation.status != "notRequired" {
                Picker("餐厅确认的日期", selection: $reservation.date) {
                    Text("尚未确认").tag("")
                    ForEach(days) { Text($0.date).tag($0.date) }
                }
                Toggle("已确认预约时间", isOn: Binding(get: { !reservation.time.isEmpty }, set: { reservation.time = $0 ? "12:00" : "" }))
                if !reservation.time.isEmpty {
                    DatePicker("餐厅确认的时间", selection: reservationTime, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, TripClock.calendar.timeZone).environment(\.locale, Locale(identifier: "en_GB"))
                }
                TextField("确认号 · 选填", text: $reservation.reference).textInputAutocapitalization(.never).autocorrectionDisabled()
                PlanNoteInput(text: $reservation.notes, placeholder: "例如：已付订金、取消期限、饮食要求", minHeight: 90)
                if reservation.status == "booked" && (reservation.date.isEmpty || reservation.time.isEmpty) {
                    Label("请填写餐厅确认的日期与时间后保存。", systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(TripStyle.coral)
                }
            }
        } header: { Text("我们的预约") } footer: { Text("由我们手动记录，不会向餐厅发送预订、更改或取消请求。时间均为当地时间。") }
    }
}

struct DiningStopDetail: View {
    @Environment(TripStore.self) private var store
    let itemID: String
    @State private var edit: Stop?
    private var dayIndex: Int? { store.plan.days.firstIndex { $0.items.contains { $0.uid == itemID } } }
    private var item: Stop? { dayIndex.flatMap { index in store.plan.days[index].items.first { $0.uid == itemID } } }
    var body: some View {
        Group {
            if let index = dayIndex, let item, let place = store.place(item.place) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SectionTitle(title: place.name, subtitle: store.plan.days[index].date + " · " + MealPlan.label(item.meal?.kind ?? ""))
                        Text(item.scheduleLabel(fallbackHours: place.hours)).font(.headline).foregroundStyle(TripStyle.green)
                        if let reservation = item.meal?.reservation {
                            PaperCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(reservation.label, systemImage: reservation.status == "booked" ? "checkmark.seal" : "calendar")
                                    Text("\(reservation.partySize) 人").font(.subheadline)
                                    if !reservation.date.isEmpty || !reservation.time.isEmpty { Text("预约：\(reservation.date) \(reservation.time)").font(.subheadline) }
                                    if !reservation.reference.isEmpty { Text("确认号：" + reservation.reference).textSelection(.enabled) }
                                    if !reservation.notes.isEmpty { Text(reservation.notes).font(.subheadline).textSelection(.enabled) }
                                }
                            }
                        }
                        ForEach(DiningSchedule.warnings(item: item, day: store.plan.days[index], places: store.allPlaces, venue: store.content.dining?.venue(place.id)), id: \.self) {
                            Label($0, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(TripStyle.coral)
                        }
                        if !item.note.isEmpty { Text(item.note).font(.subheadline).textSelection(.enabled) }
                        Button("编辑用餐与预约", systemImage: "pencil") { edit = item }.buttonStyle(.glassProminent)
                        if let venue = store.content.dining?.venue(place.id) {
                            DestinationMapButton(query: venue.address.isEmpty ? venue.en : venue.address, name: venue.en, coordinates: venue.coordinates.map { [$0.latitude, $0.longitude] }).buttonStyle(.glass)
                            if let url = URL(string: venue.booking.url), !venue.booking.url.isEmpty {
                                Link(!venue.isRestaurant ? "查看地点与到店信息 ↗" : (url.host == "guide.michelin.com" ? "从米其林查看餐厅与预约入口 ↗" : "打开官方预约入口 ↗"), destination: url)
                            }
                        }
                        NavigationLink { DiningDetail(place: place) } label: { Label("餐厅详情、费用与攻略", systemImage: "book.pages") }
                    }.padding(22)
                }
            } else { ContentUnavailableView("这餐已移除", systemImage: "fork.knife", description: Text("返回行程可查看最新安排。")) }
        }.background(TripStyle.paper).navigationTitle("这一餐").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $edit) { value in
            if let place = store.place(value.place) { NavigationStack { MealEditor(place: place, day: dayIndex ?? store.selectedDay, item: value) } }
        }
    }
}

struct ScheduledPlaceDestination: View {
    let item: Stop
    let place: Place
    var body: some View {
        if place.isDining { DiningStopDetail(itemID: item.uid) }
        else { PlaceDetail(place: place) }
    }
}
