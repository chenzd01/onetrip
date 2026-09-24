import SwiftUI

struct SyncView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [String: MergeChoice] = [:]
    var body: some View {
        Form {
            Section {
                SyncIndicator()
                Text(store.syncStatus).font(.subheadline).foregroundStyle(.secondary)
                if store.isShared {
                    Text("行程、清单、预算、住宿和票券自动共享。离线修改先保存在本机，联网后自动同步。").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("所有修改都保存在这部手机上，可在「离线资料与备份」导出 JSON。多人共享行程需要自建可选后端，并在构建配置中填写 TRIP_SERVER_URL，详见 docs/zh/backend.md。").font(.footnote).foregroundStyle(.secondary)
                }
                if let date = store.lastSyncedAt {
                    LabeledContent("最近同步") { Text(date, format: .dateTime.hour().minute().second()) }
                }
                if let failure = store.syncFailure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
                if store.editingForms > 0 { Text("请先保存或关闭正在编辑的表单。").font(.footnote) }
            }
            if store.isShared { Section {
                Button {
                    Task { await store.synchronize() }
                } label: {
                    HStack {
                        if store.busy { ProgressView() }
                        Label(store.busy ? "正在同步…" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                }.disabled(store.busy || store.hasConflicts || store.editingForms > 0)
            } }
            if store.hasConflicts {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(store.conflicts.count) 处修改需要确认").font(.headline)
                        Text("自动同步已暂停。对比下方内容，逐项选择保留本地或云端。").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(store.conflicts) { conflict in
                        ConflictCard(conflict: conflict,
                                     presentation: ConflictPresentation(content: store.content, plans: [store.plan] + [store.conflictPlan].compactMap { $0 }),
                                     choice: Binding(get: { choices[conflict.path] }, set: { choices[conflict.path] = $0 }))
                    }
                    Text("已选择 \(store.conflicts.filter { choices[$0.path] != nil }.count) / \(store.conflicts.count) 处")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("应用选择并同步") { store.resolve(choices); choices = [:] }
                        .disabled(store.conflicts.contains { choices[$0.path] == nil })
                    Text("应用后会合并所选内容并同步到云端；如果期间又有新的冲突，会再次请你确认。").font(.caption).foregroundStyle(.secondary)
                }

            }
        }.navigationTitle("共享行程").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}

struct SyncIndicator: View {
    @Environment(TripStore.self) private var store
    private var label: String {
        if !store.isShared { return "仅本机" }
        if store.hasConflicts { return "待确认" }
        if !store.isLoggedIn { return "未连接" }
        if store.pending { return store.busy ? "同步中" : "待同步" }
        return store.syncVerified ? "已同步" : "待连接"
    }
    private var icon: String {
        if !store.isShared { return "iphone" }
        if store.hasConflicts { return "exclamationmark.triangle.fill" }
        if !store.isLoggedIn { return "icloud.slash" }
        if store.pending { return "arrow.triangle.2.circlepath" }
        return store.syncVerified ? "checkmark.icloud.fill" : "icloud.slash"
    }
    private var color: Color {
        if !store.isShared { return .secondary }
        if store.hasConflicts || store.pending { return .orange }
        return store.isLoggedIn && store.syncVerified ? TripStyle.green : .secondary
    }
    var body: some View {
        Label(label, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(color)
            .frame(minHeight: 44)
            .accessibilityLabel("共享同步，" + label + "，" + store.syncStatus)
    }
}

private struct ConflictCard: View {
    let conflict: MergeConflict
    let presentation: ConflictPresentation
    @Binding var choice: MergeChoice?
    @State private var showUnchanged = false
    var body: some View {
        let rows = presentation.rows(conflict)
        VStack(alignment: .leading, spacing: 16) {
            Text(presentation.title(conflict)).font(.headline).fixedSize(horizontal: false, vertical: true)
            ForEach(rows.filter { showUnchanged || $0.changed }) { row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.title).font(.caption).foregroundStyle(.secondary)
                    version("本地 · 这部手机", value: row.local, selected: choice == .local, changed: row.changed)
                    version("云端 · 共享行程", value: row.remote, selected: choice == .remote, changed: row.changed)
                }
            }
            if rows.contains(where: { !$0.changed }) {
                Toggle("查看相同内容", isOn: $showUnchanged).font(.subheadline)
            }
            ViewThatFits(in: .horizontal) {
                HStack { selection(.local, "保留本地"); selection(.remote, "保留云端") }
                VStack { selection(.local, "保留本地"); selection(.remote, "保留云端") }
            }
        }.padding(.vertical, 12)
    }
    private func version(_ title: String, value: String, selected: Bool, changed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(selected ? TripStyle.green.opacity(0.1) : Color.secondary.opacity(0.06), in: .rect(cornerRadius: 12))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(changed ? Color.orange : Color.clear).frame(width: 3).padding(.vertical, 10) }
    }
    private func selection(_ value: MergeChoice, _ title: String) -> some View {
        Button { choice = value } label: {
            Label(title, systemImage: choice == value ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }.buttonStyle(.bordered).tint(choice == value ? TripStyle.green : .secondary)
            .accessibilityAddTraits(choice == value ? .isSelected : [])
    }
}
