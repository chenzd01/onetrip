import SwiftUI

struct ScheduleFields: View {
    @Binding var draft: ScheduleDraft

    var body: some View {
        Section {
            Toggle("设置时间段", isOn: $draft.isTimed)
            if draft.isTimed {
                DatePicker("开始", selection: $draft.start, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .accessibilityIdentifier("schedule-start")
                DatePicker(draft.endsNextDay ? "结束 · 次日" : "结束", selection: $draft.end, displayedComponents: .hourAndMinute)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .accessibilityIdentifier("schedule-end")
                Toggle("次日结束", isOn: $draft.endsNextDay)
                if let message = draft.validationMessage {
                    Label(message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(TripStyle.coral)
                } else {
                    Label("\(draft.time) + \(Stop.durationLabel(draft.durationMinutes))", systemImage: "clock")
                        .font(.subheadline.weight(.medium)).foregroundStyle(TripStyle.green)
                        .accessibilityLabel("开始 \(draft.time)，持续 \(Stop.durationLabel(draft.durationMinutes))\(draft.endsNextDay ? "，次日结束" : "")")
                        .accessibilityIdentifier("schedule-summary")
                }
            }
        } header: { Text("安排时间") } footer: {
            Text(draft.isTimed ? "当地时间 · 自动计算时长。新增或修改时间段后，当天安排会按开始时间排序，也可再手动拖动调整。" : "时间未定也可以先加入行程，之后再补充。")
        }
        .environment(\.timeZone, TripClock.calendar.timeZone)
    }
}

struct AddPlaceEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let place: Place
    var onAdded: (() -> Void)?
    @State private var day: Int
    @State private var schedule: ScheduleDraft
    @State private var note = ""

    init(place: Place, day: Int, onAdded: (() -> Void)? = nil) {
        self.place = place
        self.onAdded = onAdded
        _day = State(initialValue: day)
        _schedule = State(initialValue: ScheduleDraft(suggestedHours: place.hours))
    }
    var body: some View {
        Form {
            Section {
                Text(place.name).font(.headline).foregroundStyle(TripStyle.green)
                Picker("日期", selection: $day) {
                    ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, day in Text(day.date).tag(index) }
                }
            }
            ScheduleFields(draft: $schedule)
            Section("给我们的备注 · 选填") { PlanNoteInput(text: $note) }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("放进行程").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("添加") {
                    var item = Stop(uid: UUID().uuidString.lowercased(), place: place.id, time: "", note: note)
                    schedule.apply(to: &item)
                    if store.editSchedule({ $0.days[day].items.append(item) }) {
                        store.selectedDay = day; store.activeTab = 1
                        if let onAdded { onAdded() } else { dismiss() }
                    }
                }.disabled(!schedule.isValid)
            }
        }
        .onAppear { store.editingForms += 1 }.onDisappear { store.editingForms -= 1 }
    }
}
