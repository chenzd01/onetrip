import SwiftUI

struct TodayView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var now = TripClock.now
    private var context: DayContext { DayContext(plan: store.plan, places: store.allPlaces, now: now) }
    private var date: String { TripClock.dayKey(now) }
    private var beforeTrip: Bool { context.phase == .before }
    private var afterTrip: Bool { context.phase == .after }
    private var pendingPreparation: [Preparation] {
        store.content.preparation.filter { $0.isDue(on: date) && store.plan.checks[$0.id] != true }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(beforeTrip ? "出发准备" : afterTrip ? "旅行回顾" : "今日安排")
                        .font(.title2.weight(.semibold)).foregroundStyle(TripStyle.green)
                        .accessibilityAddTraits(.isHeader)
                    Text(daySummary).font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)
                if !pendingPreparation.isEmpty { preparationProgress }
                if beforeTrip {
                    ForEach(Array(pendingPreparation.prefix(3))) { prep in
                        NavigationLink { PreparationDetail(prep: prep) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "circle").font(.title3).foregroundStyle(TripStyle.green.opacity(0.4))
                                VStack(alignment: .leading, spacing: 5) { Text(prep.title).font(.subheadline.weight(.medium)); Text(prep.group).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(18).background(TripStyle.card, in: .rect(cornerRadius: 20))
                        }.buttonStyle(.plain)
                    }
                } else if afterTrip {
                    ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, day in
                        Button { store.selectedDay = index; store.activeTab = 1 } label: {
                            PaperCard { HStack { Text(day.date.suffix(5)); Text(day.title); Spacer(); Image(systemName: "arrow.right") } }
                        }.buttonStyle(.plain)
                    }
                } else {
                    if let day = context.day {
                        if day.items.isEmpty { Text("今天还没有安排，去行程里添加想去的地方吧。").foregroundStyle(.secondary) }
                        ForEach(day.items) { item in
                            if let place = store.place(item.place) { NavigationLink { ScheduledPlaceDestination(item: item, place: place) } label: { StopRow(item: item, place: place) }.buttonStyle(.plain) }
                        }
                    }
                    if !context.ticketPlaces.isEmpty {
                        ForEach(context.ticketPlaces, id: \.self) { id in
                            if let place = store.place(id) { NavigationLink { TicketListView(place: place) } label: { Label(place.name + " · 打开票券", systemImage: "ticket").padding(16) }.buttonStyle(.glass) }
                        }
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            if context.tonight.isEmpty { Text(date == store.plan.days.last?.date ? "今天返程，记得确认行李寄存和去机场的时间。" : "今晚还没有登记住宿，出发前记得补齐。").font(.subheadline).foregroundStyle(.secondary) }
                            ForEach(context.tonight) { stay in
                                Text(stay.name).font(.title3)
                                Text(stay.address).font(.caption).textSelection(.enabled)
                                StayNavigationButton(stay: stay)
                            }
                            ForEach(context.checkingOut) { stay in Text("今天 \(stay.checkOutTime) 前退房 · \(stay.name)").font(.subheadline).foregroundStyle(TripStyle.coral) }
                            NavigationLink("管理住宿") { StaysView() }
                        }
                    }
                }
                if context.phase == .traveling, let day = context.day { DayRouteCard(day: day, tab: 0) }
                Button {
                    if store.liveActivity.isActive { Task { await store.liveActivity.end() } }
                    else { do { try store.liveActivity.start(store.travelSchedule) } catch { store.error = error.localizedDescription } }
                } label: { Label(store.liveActivity.isActive ? "结束锁屏实时活动" : "把接下来的安排放到锁屏", systemImage: "platter.filled.top.iphone") }.buttonStyle(.glass)
                Text("锁屏安排可能暂停更新，打开 App 可刷新。").font(.caption).foregroundStyle(.secondary)
                Button { store.selectedDay = store.todayIndex; store.activeTab = 1 } label: {
                    HStack { Text(beforeTrip || afterTrip ? "查看全部行程" : "查看今日完整行程"); Spacer(); Image(systemName: "arrow.right") }.padding(8)
                }.buttonStyle(.glassProminent)
            }.padding(.horizontal, 22).padding(.bottom, 24)
        }.background(TripStyle.paper)
        .task {
            while !Task.isCancelled {
                now = TripClock.now
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    private var daySummary: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TripClock.calendar.timeZone
        formatter.dateFormat = "M月d日 EEEE"
        let today = formatter.string(from: now)
        if beforeTrip {
            let remaining = max(0, TripClock.daysUntilDeparture(now))
            return today + (remaining == 0 ? " · 今天出发" : " · 距出发 \(remaining) 天")
        }
        return today + " · 当地时间"
    }
    private var preparationProgress: some View {
        Button { store.activeTab = 3 } label: {
            VStack(alignment: .leading, spacing: 10) {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))) {
                    Label("行前准备", systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.medium))
                    if !typeSize.isAccessibilitySize { Spacer() }
                    HStack(spacing: 12) {
                        Text("\(store.checkCount)/\(store.content.preparation.count)")
                            .font(.subheadline.monospacedDigit())
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                ProgressView(value: Double(store.checkCount), total: Double(max(1, store.content.preparation.count)))
                    .tint(TripStyle.green)
            }
            .foregroundStyle(TripStyle.green)
            .padding(16)
            .background(TripStyle.card, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("行前准备，已完成 \(store.checkCount) 项，共 \(store.content.preparation.count) 项")
        .accessibilityHint("打开行囊，查看和修改准备清单")
    }
}
