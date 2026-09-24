import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct TravelKitView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkFeedback = false
    @State private var onlyIncomplete = true
    private var visiblePreparation: [Preparation] {
        store.content.preparation.filter { !onlyIncomplete || store.plan.checks[$0.id] != true }
    }
    var body: some View {
        List {
            Section {
                Toggle(isOn: $onlyIncomplete) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("仅显示未完成").font(.subheadline.weight(.semibold))
                        Text(onlyIncomplete ? "已收起 \(store.checkCount) 项已完成事项" : "正在显示全部 \(store.content.preparation.count) 项")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(TripStyle.green)
                .accessibilityLabel("仅显示未完成")
                .accessibilityHint(onlyIncomplete ? "关闭后显示全部准备事项" : "开启后仅显示未完成的准备事项")
                .accessibilityIdentifier("preparation.only-incomplete")
            }.listRowBackground(TripStyle.card)
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Eyebrow(text: "PACK LIGHT. FEEL READY.")
                    Text("行囊轻一点，\n心里踏实一点。").font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                    ProgressView(value: Double(store.checkCount), total: Double(store.content.preparation.count)).tint(TripStyle.green)
                    Text("\(store.checkCount) / \(store.content.preparation.count) 项准备好了").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 12).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            Section("这次旅行的重要资料") {
                NavigationLink { FlightsView() } label: { Label("去程与返程航班", systemImage: "airplane") }
                NavigationLink { StaysView() } label: { Label("我们的住宿", systemImage: "bed.double") }
                NavigationLink { BudgetView() } label: { Label("旅行预算", systemImage: "yensign.circle") }
                NavigationLink { PhrasebookView() } label: { Label("旅行短句 · " + TripConfig.current.speech.label, systemImage: "character.bubble") }
                NavigationLink { ReminderView() } label: { Label("出发与票券提醒", systemImage: "bell") }
                NavigationLink { OfflineView() } label: { Label("离线资料与备份", systemImage: "arrow.down.circle") }
            }.listRowBackground(TripStyle.card)
            Section { NavigationLink { AboutView() } label: { Label("关于、隐私与内容来源", systemImage: "info.circle") } }.listRowBackground(TripStyle.card)
            if onlyIncomplete && visiblePreparation.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("全部准备好了", systemImage: "checkmark.circle.fill")
                            .font(.headline).foregroundStyle(TripStyle.green)
                        Text("已完成事项已收起，随时可以展开查看或取消勾选。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("显示全部") { onlyIncomplete = false }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("preparation.show-all")
                    }.padding(.vertical, 6)
                }.listRowBackground(TripStyle.card)
            }
            ForEach(Array(NSOrderedSet(array: visiblePreparation.map(\.group))) as? [String] ?? [], id: \.self) { group in
                Section(group) {
                    ForEach(visiblePreparation.filter { $0.group == group }.sorted {
                        store.plan.checks[$0.id] != true && store.plan.checks[$1.id] == true
                    }) { prep in
                        HStack(spacing: 14) {
                            Button { if store.edit({ $0.checks[prep.id] = !($0.checks[prep.id] ?? false) }) { checkFeedback.toggle() } } label: { Image(systemName: store.plan.checks[prep.id] == true ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 44, height: 44) }.buttonStyle(.borderless).accessibilityLabel((store.plan.checks[prep.id] == true ? "取消完成：" : "完成：") + prep.title)
                            NavigationLink { PreparationDetail(prep: prep) } label: { VStack(alignment: .leading, spacing: 5) { Text(prep.title).font(.subheadline.weight(.medium)); Text(prep.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) } }
                        }.listRowBackground(TripStyle.card)
                    }
                }
            }
            if store.canUndo { Section { Button("撤销上次修改", systemImage: "arrow.uturn.backward") { store.undo() } } }
            Section("到了当地，随手查") {
                ForEach(store.content.references) { guide in
                    NavigationLink(guide.title) { ScrollView { VStack(alignment: .leading, spacing: 20) { Text(guide.title).font(.title2.weight(.semibold)); Text(guide.body).font(.body).lineSpacing(7).textSelection(.enabled); SourceLinks(links: guide.links) }.padding(24) }.background(TripStyle.paper).navigationTitle("当地指南").navigationBarTitleDisplayMode(.inline) }
                }
            }.listRowBackground(TripStyle.card)
        }.scrollContentBackground(.hidden).background(TripStyle.paper)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.plan.checks)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: onlyIncomplete)
        .sensoryFeedback(.success, trigger: checkFeedback)
    }
}
struct PreparationDetail: View {
    @Environment(TripStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionFeedback = false
    var prep: Preparation
    private var isReady: Bool { store.plan.checks[prep.id] == true }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: prep.group)
                Text(prep.title).font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                Text(prep.summary).font(.title3).foregroundStyle(.secondary)
                ForEach(Array(prep.body.enumerated()), id: \.offset) { i, paragraph in
                    PaperCard { VStack(alignment: .leading, spacing: 14) { Eyebrow(text: String(format: "%02d", i+1)); Text(paragraph).font(.body).lineSpacing(7).textSelection(.enabled) } }
                }
                if let path = prep.guideImage { PreparationGuideImage(path: path) }
                SourceLinks(links: prep.links)
                if let copy = prep.copy, !copy.isEmpty { Button("复制办理说明", systemImage: "doc.on.doc") { UIPasteboard.general.string = copy }.buttonStyle(.glass) }
            }.padding(22)
        }.background(TripStyle.paper).navigationTitle("行前准备").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
                    if store.edit({ $0.checks[prep.id] = !($0.checks[prep.id] ?? false) }) { completionFeedback.toggle() }
                }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .scaleEffect(isReady && !reduceMotion ? 1.08 : 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isReady ? "已准备好" : "还没准备好").font(.headline)
                        Text(isReady ? "已经记下啦 · 轻点取消完成" : "准备妥当后，轻点打勾").font(.caption)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 12).padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(isReady ? TripStyle.green : Color(uiColor: .systemGray))
            .accessibilityLabel("准备状态")
            .accessibilityValue(isReady ? "已准备好，已勾选" : "未准备好，未勾选")
            .accessibilityHint(isReady ? "轻点取消完成" : "轻点标记为已准备好")
            .accessibilityIdentifier("preparation-completion")
            .sensoryFeedback(.selection, trigger: completionFeedback)
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
    }
}
struct PreparationGuideImage: View {
    let path: String
    @State private var image: UIImage?
    @State private var showOriginal = false
    @State private var photoSaver = PhotoSaveController()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("图片攻略").font(.headline)
            Text("原图完整保留 · 轻点后双指缩放，向下滑动阅读").font(.caption).foregroundStyle(.secondary)
            if let image {
                Button { showOriginal = true } label: {
                    Image(uiImage: image).resizable().scaledToFit()
                }.buttonStyle(.plain).accessibilityLabel("放大阅读攻略原图")
                    .contextMenu {
                        Button("保存到相册", systemImage: "square.and.arrow.down") { photoSaver.save(path: path) }.disabled(photoSaver.isSaving)
                    }
                    .accessibilityAction(named: "保存到相册") { photoSaver.save(path: path) }
                Button("保存攻略原图到相册", systemImage: "square.and.arrow.down") { photoSaver.save(path: path) }
                    .buttonStyle(.glass).disabled(photoSaver.isSaving)
            } else {
                ContentUnavailableView("图片暂未加载", systemImage: "photo")
            }
        }
        .task(id: path) {
            if let url = ContentCatalog.resource(path) { image = UIImage(contentsOfFile: url.path) }
        }
        .photoSaveFeedback(photoSaver)
        .fullScreenCover(isPresented: $showOriginal) {
            ImageGallery(selection: .init(title: "攻略原图", pages: [.init(path: path, caption: "图片攻略", credit: "原图完整保留", zoomProgressKey: "preparation-guide-" + path)], index: 0))
        }
    }
}
struct FlightsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TripStore.self) private var store
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            SectionTitle(title: "从\(store.content.trip.homeCity)，到\(store.content.trip.destination.name)", subtitle: "所有时间均为当地时间")
            ForEach(Array(store.content.flights.enumerated()), id: \.element.id) { index, flight in
                PaperCard { VStack(alignment: .leading, spacing: 22) {
                    HStack { Eyebrow(text: index == 0 ? "OUTBOUND · 去程" : index == store.content.flights.count - 1 ? "HOMEBOUND · 返程" : "FLIGHT · 航班"); Spacer(); Image(systemName: "airplane") }
                    Text(flight.number).font(.system(.largeTitle, design: .rounded, weight: .medium)).foregroundStyle(TripStyle.green)
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top))) {
                        VStack(alignment: .leading, spacing: 6) { Text(String(flight.departure.suffix(5))).font(.title); Text(flight.from).font(.caption); Text(String(flight.departure.prefix(10))).font(.caption2).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "arrow.right").foregroundStyle(TripStyle.coral).padding(.top, 12); Spacer()
                        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 6) { Text(String(flight.arrival.suffix(5))).font(.title); Text(flight.to).font(.caption); Text(String(flight.arrival.prefix(10))).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Divider()
                    Label("以航司最新通知为准，出发前核对出票及行李", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                } }
            }
        }.padding(22) }.background(TripStyle.paper).navigationTitle("我们的航班").navigationBarTitleDisplayMode(.inline)
    }
}
struct StaysView: View {
    @Environment(TripStore.self) private var store
    @State private var editing: Stay?
    var body: some View {
        List {
            if (store.plan.stays ?? []).isEmpty { ContentUnavailableView("给这次旅行找个落脚点", systemImage: "bed.double", description: Text("按订单填写入住和退房日期。凌晨到店需要确认前一晚保留房间。")) }
            ForEach(store.plan.stays ?? []) { stay in
                Section {
                    StayCopyRow(label: "酒店中文名", value: stay.name) { editing = stay }
                    StayCopyRow(label: "酒店英文名", value: stay.nameEnglish ?? "") { editing = stay }
                    StayNavigationButton(stay: stay)
                    StayCopyRow(label: "英文地址", value: stay.address) { editing = stay }
                    StayCopyRow(label: "前台电话", value: stay.phone) { editing = stay }
                    if let phoneURL = stay.phoneURL { Link(destination: phoneURL) { Label("拨打前台电话", systemImage: "phone") } }
                    StayCopyButton(label: "住宿资料", value: stay.copyText, title: "复制整份住宿资料")
                    LabeledContent("入住", value: stay.checkIn + " " + stay.checkInTime)
                    LabeledContent("退房", value: stay.checkOut + " " + stay.checkOutTime)
                    if !stay.notes.isEmpty { Text(stay.notes).font(.footnote).foregroundStyle(.secondary) }
                    Button("编辑住宿", systemImage: "pencil") { editing = stay }
                }.swipeActions { Button("删除", role: .destructive) { _ = store.edit { $0.stays?.removeAll { $0.id == stay.id } } } }
            }
            Section { Button("添加住宿", systemImage: "plus") { editing = Stay() } }
        }.navigationTitle("我们的住宿").sheet(item: $editing) { stay in NavigationStack { StayEditor(stay: stay) } }
    }
}
extension Stay {
    var phoneURL: URL? {
        let number = phone.filter { "+0123456789".contains($0) }
        guard number.contains(where: { "0123456789".contains($0) }) else { return nil }
        return URL(string: "tel:" + number)
    }
    var copyText: String {
        [("酒店中文名", name), ("酒店英文名", nameEnglish ?? ""), ("英文地址", address), ("前台电话", phone),
         ("入住", checkIn + " " + checkInTime), ("退房", checkOut + " " + checkOutTime)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.0)：\($0.1)" }.joined(separator: "\n")
    }
}

struct StayCopyRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let label: String
    let value: String
    var edit: () -> Void
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 14))) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "尚未填写" : value)
                    .font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("补充", systemImage: "plus.circle", action: edit).frame(minHeight: 44).accessibilityLabel("补充" + label)
            } else {
                StayCopyButton(label: label, value: value, title: "复制", copiedTitle: "已复制")
                    .fixedSize(horizontal: true, vertical: false)
            }
        }.padding(.vertical, 4)
    }
}

struct StayCopyButton: View {
    let label: String
    let value: String
    var title: String? = nil
    var copiedTitle: String? = nil
    @State private var copyCount = 0
    @State private var copied = false
    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true; copyCount += 1
            UIAccessibility.post(notification: .announcement, argument: "已复制" + label)
        } label: {
            Label(copied ? (copiedTitle ?? "已复制" + label) : (title ?? "复制" + label), systemImage: copied ? "checkmark" : "doc.on.doc")
                .font(.subheadline).frame(minHeight: 44)
        }.buttonStyle(.borderless)
        .accessibilityLabel("复制" + label)
        .accessibilityValue(copied ? "已复制" : "")
        .sensoryFeedback(.success, trigger: copyCount)
        .task(id: copyCount) {
            guard copyCount > 0 else { return }
            do { try await Task.sleep(for: .seconds(2)); copied = false } catch {}
        }
    }
}
struct StayEditor: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var stay: Stay
    var body: some View {
        Form {
            Section {
                TextField("酒店中文名", text: $stay.name, prompt: Text("按订单填写中文名"))
                TextField("酒店英文名", text: Binding(get: { stay.nameEnglish ?? "" }, set: { stay.nameEnglish = $0 }), prompt: Text("按订单填写英文名"))
                    .textInputAutocapitalization(.words).autocorrectionDisabled()
                TextField("英文地址", text: $stay.address).textContentType(.fullStreetAddress)
                TextField("前台电话", text: $stay.phone, prompt: Text("含国家区号，如 +1 …")).keyboardType(.phonePad).textContentType(.telephoneNumber)
            } header: { Text("酒店资料") } footer: { Text("旧酒店名称原样保留，请按订单核对双语名称。英文名和电话可稍后补充。") }
            Section("按订单日期填写") {
                TextField("入住 YYYY-MM-DD", text: $stay.checkIn); TextField("退房 YYYY-MM-DD", text: $stay.checkOut)
                TextField("入住时间 HH:mm", text: $stay.checkInTime); TextField("退房时间 HH:mm", text: $stay.checkOutTime)
                Toggle("已确认凌晨到店保留房间", isOn: $stay.lateArrival)
            }
            Section("入住与行李寄存备注") { TextEditor(text: $stay.notes).frame(minHeight: 110) }
        }.navigationTitle("住宿资料").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("保存") { if store.edit({ p in var stays = p.stays ?? []; stays.removeAll { $0.id == stay.id }; stays.append(stay); p.stays = stays.sorted { $0.checkIn < $1.checkIn } }) { dismiss() } } }
        }.onAppear { store.editingForms += 1 }.onDisappear { store.editingForms -= 1 }
    }
}
struct OfflineView: View {
    @Environment(TouchStore.self) private var touch
    @Environment(TripStore.self) private var store
    @State private var backup: URL?
    @State private var importing = false
    @State private var checkResult = ""
    @State private var importData: Data?
    @State private var confirmingImport = false
    var body: some View {
        List {
            Section("随 App 安装的资料") {
                Label("\(store.content.posts.count) 篇攻略 · \(store.content.posts.reduce(0) { $0 + $1.images.count }) 张攻略原图", systemImage: "checkmark.circle.fill")
                Label("地点实景、酒店照片与 \(store.content.preparation.count) 项准备", systemImage: "checkmark.circle.fill")
                Text("内置资源打开图片不使用流量。地图导航、原平台链接需要网络。").font(.footnote).foregroundStyle(.secondary)
                Button("检查内置资源是否齐全", systemImage: "checkmark.shield") {
                    Task {
                        let result = await Task.detached {
                            guard let url = ContentCatalog.resource("manifest.json"), let data = try? Data(contentsOf: url) else { return "资源清单缺失" }
                            struct Entry: Decodable { var path: String; var bytes: Int; var sha256: String }
                            guard let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return "资源清单无效" }
                            let missing = entries.filter { e in guard let u = ContentCatalog.resource(e.path), let data = try? Data(contentsOf: u, options: .mappedIfSafe) else { return true }; return data.count != e.bytes || AttachmentStore.hash(data) != e.sha256 }
                            return missing.isEmpty ? "\(entries.count) 个内置文件全部齐全" : "\(missing.count) 个文件缺失或损坏"
                        }.value
                        checkResult = result
                    }
                }
                if !checkResult.isEmpty { Text(checkResult).font(.caption) }
            }
            Section("共享资料") {
                Text(store.syncStatus)
                ForEach(store.ticketFiles) { file in
                    LabeledContent(file.name, value: store.attachmentStatus[file.id] ?? "检查中…").font(.subheadline)
                }
                if store.isShared && !store.ticketFiles.isEmpty {
                    Button("下载全部票券附件（允许移动网络）", systemImage: "arrow.down.circle") { Task { await store.downloadMissingAttachments(cellular: true) } }
                }
                Text("后来录入的门票附件通过 Wi-Fi 自动保存；手动下载允许使用移动网络。已保存的票券不会被普通图片缓存清理。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("互动绑定") {
                if store.isShared {
                    Text(touch.bindingStatus).font(.subheadline).foregroundStyle(.secondary)
                    Button(touch.paired ? "管理绑定与通知" : "绑定这部手机", systemImage: "link") {
                        touch.showingSettings = true
                    }
                } else { Text(TouchStore.offlineNote).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("行程备份") {
                Button("导出行程 JSON", systemImage: "square.and.arrow.up") { do { backup = try store.exportBackup() } catch { store.error = error.localizedDescription } }
                if let backup { ShareLink("分享备份文件", item: backup) }
                Button("导入行程 JSON", systemImage: "square.and.arrow.down") { importing = true }
                Text("JSON 包含行程和附件引用，不包含附件原文件。导入后可撤销；连接共享行程后会参与同步。").font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("离线资料与备份").onAppear { store.refreshAttachmentStatus() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let bytes = try Data(contentsOf: url); let plan = try JSONDecoder().decode(TripPlan.self, from: bytes); try PlanValidation.validate(plan, catalog: store.content); importData = bytes; confirmingImport = true }
            catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("用备份替换当前行程？", isPresented: $confirmingImport, titleVisibility: .visible) {
            Button(store.isShared ? "导入并加入共享同步" : "导入") { if let importData { do { try store.importBackup(importData) } catch { store.error = error.localizedDescription } }; importData = nil }
            Button("取消", role: .cancel) { importData = nil }
        } message: { Text("会替换行程、清单、预算和预订资料\(store.isShared ? "，联网后同步到共享行程" : "")。可以撤销本次导入；缺失附件仍需补齐。") }
    }
}
