import SwiftUI
import UniformTypeIdentifiers
import QuickLook

struct TicketListView: View {
    @Environment(TripStore.self) private var store
    var place: Place
    @State private var editing: Ticket?
    @State private var previewURL: URL?
    @State private var exportedURL: URL?
    @State private var photoSaver = PhotoSaveController()
    @State private var deleting: Ticket?
    var body: some View {
        List {
            let drafts = store.ticketDrafts.filter { $0.placeID == place.id }
            if !drafts.isEmpty {
                Section("本机未完成的草稿") {
                    ForEach(drafts) { draft in Button(draft.ticket.title.isEmpty ? "继续填写新门票" : draft.ticket.title, systemImage: "pencil.circle") { editing = draft.ticket } }
                }
            }
            if (store.plan.tickets?[place.id] ?? []).isEmpty { ContentUnavailableView("把票券收在这里", systemImage: "ticket", description: Text("门票跟着地点保存，从今日和行程随手就能找到。")) }
            ForEach(store.plan.tickets?[place.id] ?? []) { ticket in
                Section {
                    HStack { Text(ticket.title).font(.headline); Spacer(); Text(["planned":"计划预订","booked":"已预订","used":"已使用","cancelled":"已取消"][ticket.status] ?? ticket.status).font(.caption).foregroundStyle(TripStyle.coral) }
                    Text("\(ticket.quantity) 人 · \(ticket.date.isEmpty ? "日期待定" : ticket.date) \(ticket.time)").font(.subheadline)
                    let plannedDates = store.plan.days.filter { $0.items.contains { $0.place == place.id } }.map(\.date)
                    if !ticket.date.isEmpty && !plannedDates.contains(ticket.date) { Label("票券日期与当前行程不一致，请核对", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(TripStyle.coral) }
                    if !ticket.reference.isEmpty { Text(ticket.reference).font(.title3.monospaced()).textSelection(.enabled) }
                    if !ticket.provider.isEmpty { LabeledContent("预订平台", value: ticket.provider) }
                    if !ticket.deadline.isEmpty { LabeledContent("退改截止", value: ticket.deadline.replacingOccurrences(of: "T", with: " ")) }
                    if !ticket.notes.isEmpty { Text(ticket.notes).font(.footnote).textSelection(.enabled) }
                    if let url = URL(string: ticket.url), ["http","https"].contains(url.scheme ?? "") { Link("打开预订平台 ↗", destination: url) }
                    ForEach(ticket.files) { file in
                        Button {
                            Task {
                                do { previewURL = try await store.attachments.verifiedURL(for: file) }
                                catch { store.error = "这个附件尚未完整保存在本机，请点击下面的下载按钮。" }
                            }
                        } label: {
                            HStack {
                                Image(systemName: file.type == "application/pdf" ? "doc.richtext" : "photo")
                                VStack(alignment: .leading, spacing: 5) { Text(file.name).lineLimit(2); Text(store.attachmentStatus[file.id] ?? "检查离线状态…").font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu {
                            if file.type.hasPrefix("image/") {
                                Button("保存图片到相册", systemImage: "square.and.arrow.down") { saveImage(file) }.disabled(photoSaver.isSaving)
                            }
                        }
                        .accessibilityActions {
                            if file.type.hasPrefix("image/") { Button("保存图片到相册") { saveImage(file) } }
                        }
                    }
                    if !ticket.files.isEmpty {
                        Button("下载这张票的附件（允许移动网络）", systemImage: "arrow.down.circle") { Task { await store.downloadMissingAttachments(cellular: true, files: ticket.files) } }
                    }
                    Button("分享完整离线副本", systemImage: "square.and.arrow.up") {
                        Task { do { exportedURL = try await store.attachments.export(ticket: ticket, place: place.name) } catch { store.error = "请先下载全部附件，再保存完整副本。" } }
                    }
                    Button("编辑门票", systemImage: "pencil") { editing = store.ticketDrafts.first { $0.id == ticket.id }?.ticket ?? ticket }
                    Button("删除门票记录", systemImage: "trash", role: .destructive) { deleting = ticket }
                }
            }
            Section {
                Button("添加门票", systemImage: "plus") { editing = Ticket() }.disabled((store.plan.tickets?[place.id] ?? []).count >= 12)
                Text("二维码若会动态刷新，仍需打开原预订平台。离线文件是保存时的独立副本。").font(.caption).foregroundStyle(.secondary)
                if let exportedURL { ShareLink("分享已生成的离线文件", item: exportedURL) }
            }
        }.navigationTitle(place.name + " · 门票").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ticket in NavigationStack { TicketEditor(placeID: place.id, ticket: ticket) } }
        .quickLookPreview($previewURL)
        .photoSaveFeedback(photoSaver)
        .onAppear { store.refreshAttachmentStatus() }
        .confirmationDialog("删除这条门票记录？原附件仍保留供恢复。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let ticket = deleting { Button("删除记录", role: .destructive) { if store.edit({ $0.tickets?[place.id]?.removeAll { $0.id == ticket.id } }) { store.discardTicketDraft(ticket.id) }; deleting = nil } }
        }
    }
    private func saveImage(_ file: TicketFile) {
        let attachments = store.attachments
        photoSaver.save {
            do { return try await attachments.verifiedURL(for: file) }
            catch { throw PhotoSaveError.unavailable }
        }
    }
}
struct TicketEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var placeID: String
    @State var ticket: Ticket
    @State private var importing = false
    @State private var loadingFiles = false
    var body: some View {
        Form {
            Section("门票") {
                TextField("票种名称", text: $ticket.title)
                Picker("状态", selection: $ticket.status) { Text("计划预订").tag("planned"); Text("已预订").tag("booked"); Text("已使用").tag("used"); Text("已取消").tag("cancelled") }
                Stepper("\(ticket.quantity) 人", value: $ticket.quantity, in: 1...20)
                Picker("使用日期", selection: $ticket.date) { Text("待定").tag(""); ForEach(store.plan.days) { Text($0.date).tag($0.date) } }
                TextField("时间 HH:mm", text: $ticket.time)
            }
            Section("预订资料") {
                TextField("预订平台", text: $ticket.provider)
                TextField("订单 / 取票码", text: $ticket.reference)
                TextField("预订链接", text: $ticket.url).keyboardType(.URL).textInputAutocapitalization(.never)
                TextField("退改截止 YYYY-MM-DDTHH:mm", text: $ticket.deadline)
                TextEditor(text: $ticket.notes).frame(minHeight: 100).accessibilityLabel("门票备注")
            }
            Section {
                ForEach(ticket.files) { file in HStack { Label(file.name, systemImage: file.type == "application/pdf" ? "doc" : "photo"); Spacer(); Button("移除", role: .destructive) { ticket.files.removeAll { $0.id == file.id } }.font(.caption) } }
                Button(loadingFiles ? "正在保存原始文件…" : "添加图片或 PDF", systemImage: "paperclip") { importing = true }.disabled(loadingFiles || ticket.files.count >= 8)
            } header: { Text("原始附件 · \(ticket.files.count) / 8") } footer: { Text("每个不超过 10 MB。先保存到本机，提交时上传；断网也能保留门票。取消会丢弃本次表单草稿。") }
        }.navigationTitle("门票资料").navigationBarTitleDisplayMode(.inline).interactiveDismissDisabled()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { store.discardTicketDraft(ticket.id); dismiss() }.disabled(loadingFiles) }
            ToolbarItem(placement: .confirmationAction) { Button("保存") {
                if store.edit({ p in var records = p.tickets?[placeID] ?? []; records.removeAll { $0.id == ticket.id }; records.append(ticket); if p.tickets == nil { p.tickets = [:] }; p.tickets?[placeID] = records }) { store.discardTicketDraft(ticket.id); dismiss() }
            }.disabled(loadingFiles) }
        }
        .onAppear { store.editingForms += 1 }
        .onDisappear { store.editingForms -= 1 }
        .onChange(of: ticket) { _, updated in store.saveTicketDraft(updated, placeID: placeID) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .webP, .pdf], allowsMultipleSelection: true) { result in
            Task {
                loadingFiles = true; defer { loadingFiles = false }
                do {
                    let urls = try result.get()
                    guard urls.count + ticket.files.count <= 8 else { throw TripError.message("每条门票最多 8 个附件") }
                    for url in urls {
                        let file = try await store.attachments.importFile(url)
                        if !ticket.files.contains(where: { $0.id == file.id }) { ticket.files.append(file) }
                    }
                } catch { store.error = error.localizedDescription }
            }
        }
    }
}
