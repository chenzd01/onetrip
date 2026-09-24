import Foundation
import Observation
import WidgetKit

struct SavedWorkspace: Codable {
    var plan: TripPlan
    var base: TripPlan?
    var revision: Int?
    var pending: Bool

    enum CodingKeys: String, CodingKey { case plan, base, revision, pending }
    init(plan: TripPlan, base: TripPlan?, revision: Int?, pending: Bool) {
        self.plan = plan; self.base = base; self.revision = revision; self.pending = pending
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try PlanCompatibility.decode(container.decode(JSONValue.self, forKey: .plan))
        base = try container.decodeIfPresent(JSONValue.self, forKey: .base).map { try PlanCompatibility.decode($0) }
        revision = try container.decodeIfPresent(Int.self, forKey: .revision)
        pending = try container.decode(Bool.self, forKey: .pending)
    }
}
@MainActor @Observable final class TripStore {
    let reminders = ReminderController()
    let liveActivity = LiveActivityController()
    let routePreferences: RoutePreferenceStore
    let routeService = DayRouteService()
    let content: ContentCatalog
    private(set) var plan: TripPlan
    private(set) var syncStatus = "离线内容已就绪"
    private(set) var pending = false
    private(set) var conflicts: [MergeConflict] = []
    private(set) var isLoggedIn = false
    private(set) var lastSyncedAt: Date?
    private(set) var syncFailure: String?
    var error: String?
    var activeTab = 0
    var selectedDay = 0
    var focusedStopID: String?
    var editingForms = 0
    private(set) var attachmentStatus: [String: String] = [:]
    private(set) var ticketDrafts: [TicketDraft] = []
    let attachments: AttachmentStore
    private(set) var canUndo = false
    private var history: [TripPlan] = []
    private var base: TripPlan?
    private var revision: Int?
    private var credentials: SessionCredentials?
    private var conflictRemote: RemoteSnapshot?
    private(set) var busy = false
    private(set) var syncVerified = false
    var conflictPlan: TripPlan? { conflictRemote?.state }
    private var polling: Task<Void, Never>?
    private var downloading: Task<Void, Never>?
    let api: any TripService
    private let useKeychain: Bool
    private let workspaceURL: URL
    private let draftsURL: URL
    var ticketFiles: [TicketFile] {
        var ids = Set<String>()
        return (plan.tickets ?? [:]).values.flatMap { $0 }.flatMap(\.files).filter { ids.insert($0.id).inserted }
    }
    var allPlaces: [Place] { content.catalog.places + plan.custom }
    var checkCount: Int { content.preparation.filter { plan.checks[$0.id] == true }.count }
    var todayIndex: Int { plan.days.firstIndex { $0.date == TripClock.dayKey() } ?? (TripClock.dayKey() < (plan.days.first?.date ?? "") ? 0 : plan.days.count - 1) }
    var currentDay: TripDay { plan.days[min(max(selectedDay, 0), plan.days.count - 1)] }
    // Offline mode: without a configured backend the plan lives only on this device.
    var isShared: Bool { api.isConfigured }
    static let offlineStatus = "仅本机 · 未配置共享"
    var hasConflicts: Bool { !conflicts.isEmpty }
    init(content: ContentCatalog, directory: URL? = nil, api: any TripService = TripAPI(), useKeychain: Bool = true) throws {
        self.content = content
        routePreferences = RoutePreferenceStore(tripID: content.defaults.id, directory: directory)
        self.api = api; self.useKeychain = useKeychain
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "TripWorkspace")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        workspaceURL = directory.appending(path: "workspace.json")
        draftsURL = directory.appending(path: "ticket-drafts.json")
        attachments = try AttachmentStore(directory: directory.appending(path: "Attachments"))
        if FileManager.default.fileExists(atPath: draftsURL.path) { ticketDrafts = try JSONDecoder().decode([TicketDraft].self, from: Data(contentsOf: draftsURL)) }
        if FileManager.default.fileExists(atPath: workspaceURL.path) {
            let saved = try JSONDecoder().decode(SavedWorkspace.self, from: Data(contentsOf: workspaceURL))
            try PlanValidation.validate(saved.plan, catalog: content)
            plan = saved.plan; base = saved.base; revision = saved.revision; pending = saved.pending
        } else { plan = content.defaults }
        if useKeychain {
            do { credentials = try CredentialVault.read() }
            catch { self.error = "暂时无法读取本机连接信息，将自动重新连接；本机内容已保留。" }
        }
        isLoggedIn = credentials != nil
        selectedDay = plan.days.firstIndex { $0.date == TripClock.dayKey() } ?? 0
        syncStatus = !api.isConfigured ? Self.offlineStatus : pending ? "已保存在本机 · 待同步" : "准备自动同步"
    }
    func place(_ id: String) -> Place? { allPlaces.first { $0.id == id } }
    func album(_ id: String) -> Album? { content.photos[id] }
    private func persist(plan: TripPlan, base: TripPlan?, revision: Int?, pending: Bool) throws {
        let data = try JSONEncoder().encode(SavedWorkspace(plan: plan, base: base, revision: revision, pending: pending))
        try data.write(to: workspaceURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    @discardableResult func edit(_ change: (inout TripPlan) -> Void) -> Bool {
        guard conflicts.isEmpty else { error = "请先处理共享冲突，本机草稿已保留"; return false }
        var next = plan; change(&next)
        guard next != plan else { return true }
        do {
            try PlanValidation.validate(next, catalog: content)
            // Freeze the baseline before the first edit; a later App may ship different defaults.
            let nextBase = base ?? (pending ? nil : plan)
            try persist(plan: next, base: nextBase, revision: revision, pending: true)
            history.append(plan); if history.count > 20 { history.removeFirst() }
            canUndo = true; plan = next; base = nextBase; pending = true; syncStatus = isShared ? "已保存在本机 · 待同步" : Self.offlineStatus
            updateWidget()
            refreshAttachmentStatus()
            Task { await synchronize() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    @discardableResult func editSchedule(_ change: (inout TripPlan) -> Void) -> Bool {
        edit { next in
            let previousDays = next.days
            change(&next)
            for day in next.days.indices {
                let previous = previousDays.first { $0.date == next.days[day].date }?.items ?? []
                let needsSorting = next.days[day].items.contains { item in
                    guard let old = previous.first(where: { $0.uid == item.uid }) else { return true }
                    return old.time != item.time || old.durationMinutes != item.durationMinutes
                }
                if needsSorting { next.days[day].items = next.days[day].chronologicalItems }
            }
        }
    }
    func undo() {
        guard conflicts.isEmpty, let previous = history.last else { return }
        do {
            try persist(plan: previous, base: base, revision: revision, pending: true)
            history.removeLast(); plan = previous; canUndo = !history.isEmpty; pending = true
            syncStatus = isShared ? "已撤销 · 待同步" : Self.offlineStatus; updateWidget(); Task { await synchronize() }
        } catch { self.error = error.localizedDescription }
    }
    func setForeground(_ foreground: Bool) {
        liveActivity.setForeground(foreground)
        routePreferences.setForeground(foreground && isShared)
        routeService.setForeground(foreground)
        polling?.cancel(); polling = nil
        if foreground {
            if isShared {
                polling = Task { [weak self] in
                    var delay = 3
                    while !Task.isCancelled {
                        guard let self else { return }
                        await self.synchronize()
                        delay = self.syncStatus.contains("连接") ? min(delay * 2, 60) : 3
                        try? await Task.sleep(for: .seconds(delay))
                    }
                }
            }
            updateWidget()
            refreshAttachmentStatus()
        }
    }
    func synchronize() async {
        guard isShared else { syncStatus = Self.offlineStatus; return }
        guard !busy else { return }
        guard conflicts.isEmpty else { syncStatus = "本机草稿已保留 · 需要处理冲突"; return }
        guard editingForms == 0 else { syncStatus = "编辑完成后自动同步"; return }
        busy = true; defer { busy = false }
        syncFailure = nil
        syncStatus = "正在同步"
        do {
            if (credentials?.expiresAt ?? 0) <= Date().timeIntervalSince1970 + 60 {
                try await reconnect()
            }
            guard let initialCredentials = credentials else { return }
            let remote: RemoteSnapshot?
            do { remote = try await api.snapshot(initialCredentials, since: revision) }
            catch APIError.unauthorized {
                try await reconnect()
                guard let renewed = self.credentials else { return }
                remote = try await api.snapshot(renewed, since: revision)
            }
            guard let credentials = self.credentials else { return }
            // A user may open an editor while the network request is running.
            guard editingForms == 0, !Task.isCancelled else { return }
            syncVerified = true
            if let remote { try accept(remote) }
            if !pending && conflicts.isEmpty { syncStatus = "已同步到共享行程" }
            if downloading == nil {
                downloading = Task { [weak self] in
                    await self?.downloadMissingAttachments(cellular: false)
                    self?.downloading = nil
                }
            }
            guard conflicts.isEmpty else { return }
            guard pending, let revision else {
                syncStatus = "已同步"; lastSyncedAt = Date(); return
            }
            let sending = plan
            syncStatus = "正在同步"
            do {
                let alreadyShared = Set((base?.tickets ?? [:]).values.flatMap { $0 }.flatMap(\.files).map(\.id))
                for file in sending.tickets?.values.flatMap({ $0 }).flatMap(\.files) ?? [] where !alreadyShared.contains(file.id) {
                    guard !Task.isCancelled else { return }
                    let data = try await attachments.data(for: file)
                    let uploaded = try await api.upload(data, type: file.type, credentials: credentials)
                    guard uploaded.id == file.id, uploaded.size == file.size, uploaded.type == file.type else { throw TripError.message("服务器附件校验不一致") }
                }
                guard !Task.isCancelled else { return }
                let nextRevision = try await api.save(sending, revision: revision, credentials: credentials)
                let stillPending = plan != sending
                try persist(plan: plan, base: sending, revision: nextRevision, pending: stillPending)
                base = sending; self.revision = nextRevision; pending = stillPending
                syncStatus = stillPending ? "已保存在本机 · 待同步" : "已同步到共享行程"
            } catch APIError.conflict(let latest) { try accept(latest) }
            if !pending && conflicts.isEmpty { syncStatus = "已同步"; lastSyncedAt = Date() }
        } catch { if !Task.isCancelled { report(error, interactive: false) } }
    }
    private func reconnect() async throws {
        let next = try await api.connect()
        if useKeychain { try CredentialVault.write(next) }
        credentials = next; isLoggedIn = true
    }
    private func accept(_ remote: RemoteSnapshot, choices: [String: MergeChoice] = [:]) throws {
        try PlanValidation.validate(remote.state, catalog: content)
        if !pending {
            try persist(plan: remote.state, base: remote.state, revision: remote.revision, pending: false)
            plan = remote.state; base = remote.state; revision = remote.revision
            history.removeAll(); canUndo = false; syncStatus = "已同步到共享行程"; updateWidget(); return
        }
        let result: MergeResult
        if let base {
            result = PlanMerge.merge(base: try .wrap(base), local: try .wrap(plan), remote: try .wrap(remote.state), choices: choices)
        } else if plan == remote.state {
            result = .init(value: try .wrap(plan), conflicts: [])
        } else if let choice = choices["整份行程"] {
            result = .init(value: try .wrap(choice == .local ? plan : remote.state), conflicts: [])
        } else {
            // Older offline drafts have no baseline. Never infer their edits from new defaults.
            conflicts = [.init(path: "整份行程", local: try .wrap(plan), remote: try .wrap(remote.state))]
            conflictRemote = remote; syncStatus = "本机草稿已保留 · 请选择要保留的行程"; return
        }
        if !result.conflicts.isEmpty {
            conflicts = result.conflicts; conflictRemote = remote; syncStatus = "本机草稿已保留 · 需要处理冲突"; return
        }
        var merged = try result.value.decode(TripPlan.self)
        do { try PlanValidation.validate(merged, catalog: content) }
        catch {
            if let choice = choices["整份行程"] { merged = choice == .local ? plan : remote.state }
            else {
                conflicts = [.init(path: "整份行程", local: try .wrap(plan), remote: try .wrap(remote.state))]
                conflictRemote = remote; syncStatus = "两端移动了同一安排 · 请选择版本"; return
            }
        }
        let dirty = merged != remote.state
        try persist(plan: merged, base: remote.state, revision: remote.revision, pending: dirty)
        plan = merged; base = remote.state; revision = remote.revision; pending = dirty
        conflicts = []; conflictRemote = nil; history.removeAll(); canUndo = false
        syncStatus = dirty ? "已合并独立修改 · 待同步" : "已同步到共享行程"
        updateWidget()
    }
    func resolve(_ choices: [String: MergeChoice]) {
        guard let remote = conflictRemote, conflicts.allSatisfy({ choices[$0.path] != nil }) else { return }
        do { try accept(remote, choices: choices); Task { await synchronize() } }
        catch { self.error = error.localizedDescription }
    }
    func report(_ error: Error, interactive: Bool = true) {
        syncVerified = false
        switch error {
        case APIError.unauthorized:
            syncStatus = "连接已过期 · 将自动重试"; isLoggedIn = false; credentials = nil
            syncFailure = "正在恢复共享连接，本机修改已保留。"
        case APIError.response(_, let message):
            syncStatus = "同步未完成 · 将自动重试"; syncFailure = message
        default:
            syncStatus = "暂时无法连接 · 将自动重试"; syncFailure = error.localizedDescription
        }
        if interactive { self.error = syncFailure }
    }
    func exportBackup() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: content.trip.appName + "-行程备份.json")
        try JSONEncoder().encode(plan).write(to: url, options: .atomic); return url
    }
    func importBackup(_ data: Data) throws {
        let imported = try PlanCompatibility.decode(JSONDecoder().decode(JSONValue.self, from: data))
        try PlanValidation.validate(imported, catalog: content)
        guard edit({ $0 = imported }) else { throw TripError.message(error ?? "备份未导入，本机内容已保留") }
    }
    var travelSchedule: TravelSchedule {
        let events = plan.days.flatMap { day in
            day.items.compactMap { item -> TravelSchedule.Event? in
                guard !item.time.isEmpty, let start = TripClock.date(day.date + "T" + item.time) else { return nil }
                let place = content.catalog.places.first { $0.id == item.place }
                return .init(title: place?.name ?? "自定义安排", start: start, end: start.addingTimeInterval(Double(max(1, item.duration(fallbackHours: self.place(item.place)?.hours ?? 0))) * 60), time: item.time)
            }
        }.sorted { $0.start < $1.start }
        return .init(events: events, dayKeys: plan.days.map(\.date))
    }
    func updateWidget() {
        let schedule = travelSchedule
        if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group) {
            do { try JSONEncoder().encode(schedule).write(to: directory.appending(path: "schedule.json"), options: .atomic); WidgetCenter.shared.reloadAllTimelines() }
            catch { /* Shared edits remain durable when the optional widget is unavailable. */ }
        }
        liveActivity.refresh(schedule)
        reminders.refresh(ReminderPlanner.candidates(plan: plan, content: content))
    }
    func saveTicketDraft(_ ticket: Ticket, placeID: String) {
        var drafts = ticketDrafts.filter { $0.id != ticket.id }
        drafts.append(.init(placeID: placeID, ticket: ticket))
        do { try JSONEncoder().encode(drafts).write(to: draftsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); ticketDrafts = drafts }
        catch { self.error = "门票草稿未能保存在本机：" + error.localizedDescription }
    }
    func discardTicketDraft(_ id: String) {
        let drafts = ticketDrafts.filter { $0.id != id }
        do { try JSONEncoder().encode(drafts).write(to: draftsURL, options: .atomic); ticketDrafts = drafts }
        catch { self.error = error.localizedDescription }
    }
    func refreshAttachmentStatus() {
        Task {
            for file in ticketFiles {
                if await attachments.available(file) { attachmentStatus[file.id] = "已保存离线" }
                else if attachmentStatus[file.id] != "正在下载" { attachmentStatus[file.id] = "待下载" }
            }
        }
    }
    func downloadMissingAttachments(cellular: Bool, files: [TicketFile]? = nil) async {
        guard let credentials else { return }
        for file in files ?? ticketFiles {
            if Task.isCancelled { return }
            if await attachments.available(file) { attachmentStatus[file.id] = "已保存离线"; continue }
            // A locally added pending attachment is uploaded with the next plan save.
            attachmentStatus[file.id] = "正在下载"
            do {
                let data = try await api.attachment(file, credentials: credentials, cellular: cellular)
                try await attachments.save(data, as: file); attachmentStatus[file.id] = "已保存离线"
            } catch { attachmentStatus[file.id] = cellular ? "下载失败，点击重试" : "等待 Wi-Fi 或手动下载" }
        }
    }
}
