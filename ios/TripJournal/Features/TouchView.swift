import SwiftUI
import UserNotifications

struct TouchWelcome: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(TouchStore.self) private var store
    var body: some View {
        ScrollView {
          VStack(spacing: 24) {
            HStack {
                Spacer()
                Button { store.dismissWelcome() } label: {
                    Image(systemName: "xmark").font(.body.weight(.medium)).frame(width: 44, height: 44)
                }.accessibilityLabel(store.profile == nil ? "暂不绑定" : "关闭").disabled(store.busy)
            }
            if store.needsPairingCode {
                TouchCodeEntry(explanation: "这台手机上已经有第一部手机绑定过了。请让 TA 在「行囊 → 离线资料与备份 → 互动绑定」生成配对码，在这里输入就能加入。")
            } else if store.profile == nil || store.revoked {
                TouchBindingQuestion()
            } else {
                Text("这部手机绑定好啦").font(.title3.weight(.semibold))
                if store.authorization == .notDetermined {
                    Text("想接住对方的小动作吗？").font(.subheadline).foregroundStyle(.secondary)
                    Button("允许提醒") {
                        Task { await store.allowNotifications(); store.dismissWelcome() }
                    }.buttonStyle(.borderedProminent).disabled(store.busy)
                } else {
                    Button("好啦") { store.dismissWelcome() }.buttonStyle(.borderedProminent).disabled(store.busy)
                }
            }
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(TripStyle.coral) }
            Spacer(minLength: 12)
          }.padding(.horizontal, 28)
        }.background(TripStyle.paper)
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]).presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(store.busy)
    }
}

private struct TouchBindingQuestion: View {
    @Environment(TouchStore.self) private var store
    var body: some View {
        VStack(spacing: 24) {
            Text("在这部手机上开启碰一下？").font(.title2.weight(.semibold)).foregroundStyle(TripStyle.green)
            VStack(spacing: 12) {
                ForEach(["开启"], id: \.self) { answer in
                    Button { Task { await store.bindDevice() } } label: {
                        Text(answer).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).disabled(store.busy)
                }
            }
            if store.busy { ProgressView().controlSize(.small) }
        }.padding(.vertical, 12)
    }
}

private struct TouchPairingView: View {
    @Environment(TouchStore.self) private var store
    @State private var expanded = false
    var body: some View {
        VStack(spacing: 18) {
            if store.profile == nil && !store.revoked { TouchBindingQuestion() }
            else { Text(store.bindingStatus).font(.subheadline) }
            if store.profile != nil && !store.revoked {
                TouchInvitation()
                if store.profile?.waiting == true {
                    Text("等待另一部手机确认").font(.subheadline)
                    Button("取消这次邀请") { Task { await store.pairing("cancel-invite") } }.disabled(store.busy)
                } else if !store.paired {
                    Button("重新检查绑定") { Task { await store.bindDevice(); await store.refresh() } }.disabled(store.busy)
                }
            }
            DisclosureGroup("用配对码加入 / 换手机", isExpanded: $expanded) {
                TouchCodeEntry(explanation: "让另一部已绑定的手机生成配对码，在这里输入，再由对方确认。")
            }.onChange(of: store.needsPairingCode, initial: true) { _, needed in if needed { expanded = true } }
        }
    }
}

struct TouchCodeEntry: View {
    @Environment(TouchStore.self) private var store
    @State private var code = ""
    var explanation: String
    var body: some View {
        VStack(spacing: 12) {
            Text(explanation).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            TextField("8 位配对码", text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Button("加入") {
                Task {
                    if store.revoked { store.resetRevokedDevice() }
                    if store.profile == nil { await store.enroll("旅伴") }
                    if store.profile != nil { await store.pairing("join", code: code.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
            }.buttonStyle(.borderedProminent).disabled(code.count != 8 || store.busy)
        }.padding(.top, 8)
    }
}

private struct TouchInvitation: View {
    @Environment(TouchStore.self) private var store
    var body: some View {
        if store.profile?.candidateName != nil {
            VStack(spacing: 10) {
                Text("有一部新手机等待确认").font(.headline)
                Text("确认输入邀请码的是对方的新手机。").font(.caption).foregroundStyle(.secondary)
                Button("确认，是你呀") { Task { await store.pairing("confirm") } }
                    .buttonStyle(.borderedProminent).disabled(store.busy)
                Button("不是，取消邀请") { Task { await store.pairing("cancel-invite") } }.disabled(store.busy)
            }
        } else if let invite = store.archive.invite {
            VStack(spacing: 8) {
                Text(invite.code).font(.title.monospaced().weight(.medium)).tracking(4).textSelection(.enabled)
                Text("把邀请码告诉对方，10 分钟内有效。").font(.caption).foregroundStyle(.secondary)
                Button("取消邀请") { Task { await store.pairing("cancel-invite") } }.disabled(store.busy)
            }
        }
    }
}

struct TouchSettings: View {
    @Environment(TouchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var replacing = false
    var body: some View {
        NavigationStack {
            Form {
                if !store.paired { Section { TouchPairingView() } }

                Section("通知") {
                    if let status = store.notificationStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                    LabeledContent("通知授权", value: store.notificationSettings.authorizationDescription)
                    LabeledContent("横幅", value: store.notificationSettings.bannerDescription)
                    LabeledContent("声音", value: TouchNotificationSettings.description(store.notificationSettings.sound))
                    LabeledContent("锁定屏幕", value: TouchNotificationSettings.description(store.notificationSettings.lockScreen))
                    LabeledContent("通知中心", value: TouchNotificationSettings.description(store.notificationSettings.notificationCenter))
                    Text(store.notificationSettings.showsBanner && store.notificationConnectionReady ? "每个小动作都会请求系统通知；在 App 内也会显示系统横幅。" : "使用 App 时会用卡片提醒你；系统通知连接就绪且横幅开启后，将显示系统横幅。")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.authorization == .notDetermined {
                        Text("想接住对方的小动作吗？允许通知后，锁屏也能收到。")
                        Button("允许提醒") { Task { await store.allowNotifications() } }
                    }
                    Button("打开系统通知设置") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("想更醒目，可在系统设置中开启声音、锁定屏幕与通知中心，并把横幅样式设为「持续」。静音、专注模式、通知摘要和系统设置仍会影响实际提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.paired {
                    Section("我们俩") {
                        Text(store.bindingStatus)
                        TouchInvitation()
                        Button("给对方的新手机发邀请") { replacing = true }.disabled(store.busy)
                        Text("新手机加入并经你确认后，旧手机会解绑。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("诊断记录") {
                    Text("最近的绑定、通知和小动作记录只留在本机。遇到问题时复制发给开发者，就能对上服务器日志。")
                        .font(.caption).foregroundStyle(.secondary)
                    NavigationLink("查看记录") { TouchDiagnosticsView() }
                    Button("复制诊断记录") { UIPasteboard.general.string = TouchDiagnostics.shared.report }
                }
                if let error = store.error { Section { Text(error).foregroundStyle(TripStyle.coral) } }
                if store.archive.pending != nil {
                    Section {
                        Button("确认并重试") { Task { await store.retry() } }.disabled(store.busy)
                        Button("先放下") { store.discardPending() }.disabled(store.busy)
                    }
                }
            }.navigationTitle("互动设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
                .confirmationDialog("要邀请对方的新手机吗？", isPresented: $replacing, titleVisibility: .visible) {
                    Button("生成换机邀请码") { Task { await store.invite(replace: true) } }
                } message: { Text("只有新手机加入、你确认以后，才会撤销对方旧手机的绑定。") }
        }.presentationDetents([.large])
            .task { await store.updateNotificationSettings(); await store.refresh() }
    }
}

struct TouchBanner: View {
    @Environment(TouchStore.self) private var store
    let event: TouchEvent
    var body: some View {
        HStack(spacing: 12) {
            Button { store.focusHome(); store.dismissBanner() } label: {
                HStack(spacing: 10) {
                    Image(systemName: event.kind.symbol).font(.title2).foregroundStyle(TripStyle.coral).frame(width: 38, height: 36)
                    Text(event.message).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
            }.buttonStyle(.plain)
            Button("收好", systemImage: "xmark") { store.dismissBanner() }
                .labelStyle(.iconOnly).font(.caption).frame(width: 44, height: 44)
        }.padding(.leading, 14).padding(.trailing, 4)
            .background(TripStyle.card, in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .padding(.horizontal, 20).padding(.top, 8)
            .accessibilityIdentifier("touch.incomingBanner")
    }
}

/// A non-key scene window keeps the fallback visible above any sheet. Only the card
/// receives touches; the rest of the app, including presented editors, stays interactive.
struct TouchBannerOverlay: UIViewRepresentable {
    var event: TouchEvent?
    var store: TouchStore
    func makeUIView(context: Context) -> TouchBannerAttachment {
        let view = TouchBannerAttachment()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ view: TouchBannerAttachment, context: Context) { view.update(event: event, store: store) }
    static func dismantleUIView(_ view: TouchBannerAttachment, coordinator: ()) { view.removeOverlay() }
}

final class TouchBannerAttachment: UIView {
    private var overlay: TouchBannerWindow?
    private var event: TouchEvent?
    private var store: TouchStore?
    func update(event: TouchEvent?, store: TouchStore) {
        self.event = event; self.store = store
        showIfAttached()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); showIfAttached() }
    func removeOverlay() { overlay?.isHidden = true; overlay = nil }
    private func showIfAttached() {
        guard let scene = window?.windowScene, let event, let store else { removeOverlay(); return }
        if overlay?.windowScene !== scene {
            removeOverlay()
            let newWindow = TouchBannerWindow(windowScene: scene)
            newWindow.backgroundColor = .clear
            newWindow.windowLevel = .normal + 1
            newWindow.rootViewController = TouchBannerController()
            newWindow.accessibilityViewIsModal = false
            overlay = newWindow
        }
        guard let overlay, let controller = overlay.rootViewController as? TouchBannerController else { return }
        controller.update(event: event, store: store)
        overlay.isHidden = false
    }
}

private final class TouchBannerWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let controller = rootViewController as? TouchBannerController,
              controller.cardFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

private struct TouchBannerContent: View {
    let event: TouchEvent
    let store: TouchStore
    var body: some View { TouchBanner(event: event).environment(store) }
}

private final class TouchBannerController: UIViewController {
    private var hosting: UIHostingController<TouchBannerContent>?
    var cardFrame: CGRect { hosting?.view.frame ?? .zero }
    override func loadView() { view = UIView(); view.backgroundColor = .clear }
    func update(event: TouchEvent, store: TouchStore) {
        loadViewIfNeeded()
        let content = TouchBannerContent(event: event, store: store)
        if let hosting { hosting.rootView = content }
        else {
            let hosting = UIHostingController(rootView: content)
            hosting.view.backgroundColor = .clear
            hosting.view.accessibilityViewIsModal = false
            addChild(hosting); view.addSubview(hosting.view); hosting.didMove(toParent: self)
            self.hosting = hosting
        }
        view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let hosting else { return }
        let width = view.bounds.width
        let height = hosting.sizeThatFits(in: CGSize(width: width, height: view.bounds.height)).height
        hosting.view.frame = CGRect(x: 0, y: view.safeAreaInsets.top, width: width, height: height)
    }
}

private struct TouchDiagnosticsView: View {
    @Environment(TouchStore.self) private var store
    var body: some View {
        List {
            Section {
                LabeledContent("绑定", value: store.bindingStatus)
                LabeledContent("通知权限", value: authorization)
                LabeledContent("这部手机", value: store.profile.map { String($0.memberID.prefix(8)) } ?? "未登记")
            }
            Section("最近记录") {
                ForEach(Array(TouchDiagnostics.shared.entries.reversed().enumerated()), id: \.offset) { entry in
                    Text(entry.element).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }.navigationTitle("诊断记录").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = TouchDiagnostics.shared.report }
                }
            }
    }
    private var authorization: String {
        switch store.authorization {
        case .authorized, .provisional, .ephemeral: "已允许"
        case .denied: "已关闭"
        default: "还没问过"
        }
    }
}
