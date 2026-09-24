import ActivityKit
import Foundation
import Observation

@MainActor @Observable final class LiveActivityController {
    private(set) var isActive = !Activity<TripActivityAttributes>.activities.isEmpty
    private var updating: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var schedule = TravelSchedule(events: [], dayKeys: [])

    private func content(_ schedule: TravelSchedule, now: Date = .now) -> ActivityContent<TripActivityAttributes.ContentState> {
        let snapshot = schedule.snapshot(at: now)
        let next = schedule.transitions(after: now).first ?? now.addingTimeInterval(3600)
        return ActivityContent(state: .init(title: snapshot.title, time: snapshot.time, day: TripClock.dayKey(now), nextDate: next), staleDate: min(next, now.addingTimeInterval(3600)))
    }
    func start(_ schedule: TravelSchedule) throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw TripError.message("系统尚未允许实时活动，请在设置中开启。") }
        self.schedule = schedule
        if Activity<TripActivityAttributes>.activities.isEmpty {
            _ = try Activity.request(attributes: TripActivityAttributes(tripName: TripConfig.current.appName), content: content(schedule), pushType: nil)
        }
        isActive = true
        refresh(schedule)
    }
    func end() async {
        updating?.cancel(); ticker?.cancel(); ticker = nil
        for activity in Activity<TripActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        isActive = false
    }
    func setForeground(_ foreground: Bool) {
        ticker?.cancel(); ticker = nil
        guard foreground else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh(self.schedule)
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }
    func refresh(_ schedule: TravelSchedule) {
        self.schedule = schedule
        isActive = !Activity<TripActivityAttributes>.activities.isEmpty
        updating?.cancel()
        let next = content(schedule)
        updating = Task {
            for activity in Activity<TripActivityAttributes>.activities {
                guard !Task.isCancelled else { return }
                await activity.update(next)
            }
        }
    }
}
