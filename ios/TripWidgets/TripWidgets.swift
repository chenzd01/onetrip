import SwiftUI
import WidgetKit
import ActivityKit

struct TripEntry: TimelineEntry { var date: Date; var snapshot: WidgetSnapshot }
struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripEntry { .init(date: .now, snapshot: .initial) }
    func getSnapshot(in context: Context, completion: @escaping (TripEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TripEntry>) -> Void) {
        let now = Date.now, schedule = load()
        let dates = [now] + schedule.transitions(after: now).filter { $0 < now.addingTimeInterval(86400) }
        completion(Timeline(entries: dates.map { .init(date: $0, snapshot: schedule.snapshot(at: $0)) }, policy: .after(now.addingTimeInterval(3600))))
    }
    func load() -> TravelSchedule {
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)?.appending(path: "schedule.json")
        return url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(TravelSchedule.self, from: $0) } ?? TravelSchedule(events: [], dayKeys: TripConfig.current.dayKeys)
    }
    func read() -> TripEntry { .init(date: .now, snapshot: load().snapshot(at: .now)) }

}
struct TripWidget: Widget {
    let kind = "TripToday"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TripProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Label(TripConfig.current.appName, systemImage: "leaf.fill").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(entry.snapshot.title).font(.headline)
                Text(entry.snapshot.subtitle).font(.caption).lineLimit(2)
                if !entry.snapshot.time.isEmpty { Text("计划 " + entry.snapshot.time).font(.caption.monospacedDigit()) }
            }
            .containerBackground(Color(red: 0.94, green: 0.95, blue: 0.90), for: .widget)
            .foregroundStyle(Color(red: 0.14, green: 0.30, blue: 0.25))
        }
        .configurationDisplayName(TripConfig.current.destination.name)
        .description("把这次旅行放在桌面上。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            HStack {
                Image(systemName: "leaf.fill").foregroundStyle(.green)
                VStack(alignment: .leading) { Text(context.state.title).font(.headline); Text(context.isStale ? "打开 App 刷新安排" : context.state.time.isEmpty ? "慢慢走，随心安排" : "计划 " + context.state.time).font(.caption) }
                Spacer()
                Text(context.state.day).font(.caption)
            }.padding().activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "leaf.fill") }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.time).font(.caption.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) { Text(context.state.title).font(.headline) }
            } compactLeading: { Image(systemName: "leaf.fill") }
              compactTrailing: { Text(context.state.time).font(.caption2.monospacedDigit()) }
              minimal: { Image(systemName: "leaf.fill") }
        }
    }
}
@main struct TripWidgetBundle: WidgetBundle {
    var body: some Widget { TripWidget(); TripLiveActivity() }
}
