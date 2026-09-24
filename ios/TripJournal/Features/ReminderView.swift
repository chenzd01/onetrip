import SwiftUI

struct ReminderView: View {
    @Environment(TripStore.self) private var store
    @State private var saving = false
    private var candidates: [TravelReminder] { ReminderPlanner.candidates(plan:store.plan,content:store.content) }
    var body: some View {
        List {
            Section {
                Text("提醒只在这部手机生效，由你逐项开启。所有时间按当地时区计算；修改行程后会重新安排提醒。")
                Text(store.reminders.status).font(.footnote).foregroundStyle(.secondary)
                if store.reminders.authorization == .denied { Link("打开系统通知设置", destination: URL(string:UIApplication.openSettingsURLString)!) }
            }
            ForEach(candidates) { item in
                Section {
                    Text(item.label).font(.headline)
                    Text(item.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: TripClock.calendar.timeZone))).font(.subheadline).foregroundStyle(.secondary)
                    Picker("提前提醒", selection:Binding(get:{ store.reminders.preferences[item.id] ?? -1 },set:{ value in
                        saving = true
                        Task {
                            defer { saving = false }
                            do { try await store.reminders.set(item.id,minutes:value < 0 ? nil : value,candidates:candidates) }
                            catch { store.error = error.localizedDescription }
                        }
                    })) {
                        Text("关闭").tag(-1)
                        Text("准时").tag(0)
                        Text("提前 15 分钟").tag(15)
                        Text("提前 30 分钟").tag(30)
                        Text("提前 1 小时").tag(60)
                        Text("提前 3 小时").tag(180)
                        Text("提前 1 天").tag(1440)
                    }.disabled(saving)
                }
            }
            Section { Text("票券需填写日期和时间后才可设置入场提醒。锁屏通知不显示票券名称、订单码或私人备注。已过去的提醒时间不会补发。").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("出发与票券提醒").navigationBarTitleDisplayMode(.inline)
        .task { store.reminders.refresh(candidates) }
    }
}
