import SwiftUI

@main struct TripJournalApp: App {
    @UIApplicationDelegateAdaptor(TouchAppDelegate.self) private var appDelegate
    @State private var touch = TouchStore()
    @State private var store: TripStore?
    @State private var launchError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    AppShell().environment(store).environment(touch)
                        .environment(\.openURL, OpenURLAction { url in
                            guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .systemAction }
                            Task { if !(await ExternalLinks.open(url)) { store.error = "暂时无法打开这个链接，请稍后重试。" } }
                            return .handled
                        })
                }
                else if let launchError { ContentUnavailableView("旅行手帐暂时无法打开", systemImage: "externaldrive.badge.exclamationmark", description: Text(launchError + "\n本机存档未被覆盖。")) }
                else { ProgressView("准备旅行手帐…").task {
                    do { store = try TripStore(content: ContentCatalog.load()) }
                    catch { launchError = error.localizedDescription }
                } }
            }.tint(TripStyle.green)
        }
    }
}
struct AppShell: View {
    @Environment(TouchStore.self) private var touch
    @Environment(TripStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSync = false
    @State private var visibleHomeTabs: Set<Int> = []
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    private enum Sheet: String, Identifiable { case sync, touch, welcome; var id: String { rawValue } }
    private var homeTouchVisible: Bool {
        store.isShared && visibleHomeTabs.contains(store.activeTab)
            && !touch.showingSettings && !touch.showingWelcome && !showingSync
    }
    private var homeTouchActive: Bool { homeTouchVisible && scenePhase == .active }
    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.activeTab) {
            Tab("今日", systemImage: "sun.horizon", value: 0) { navigation(tab: 0) { TodayView() }.id(touch.homeRequest) }
            Tab("行程", systemImage: "calendar", value: 1) { navigation(tab: 1) { ItineraryView() } }
            Tab("探索", systemImage: "safari", value: 2) { navigation(tab: 2) { ExploreView() } }
            Tab("行囊", systemImage: "backpack", value: 3) { navigation(tab: 3) { TravelKitView() } }
        }
        .onChange(of: homeTouchActive, initial: true) { _, visible in
            touch.homeVisible = visible
            if visible { touch.homeAppeared() }
        }
        .sheet(item: Binding<Sheet?>(get: {
            touch.showingWelcome ? .welcome : (touch.showingSettings ? .touch : (showingSync ? .sync : nil))
        }, set: { value in
            if touch.showingWelcome && value != .welcome { touch.dismissWelcome() }
            touch.showingSettings = value == .touch; showingSync = value == .sync
        })) { sheet in
            switch sheet {
            case .welcome: TouchWelcome()
            case .touch: TouchSettings()
            case .sync: NavigationStack { SyncView().toolbar {
                if store.isShared { ToolbarItem(placement: .bottomBar) { Button("互动设置") { showingSync = false; touch.showingSettings = true } } }
            } }
            }
        }
        .task { if store.isShared { touch.presentWelcomeIfNeeded() } }
        .onChange(of: touch.homeRequest) { store.activeTab = 0; showingSync = false }
        .background { TouchBannerOverlay(event: touch.banner, store: touch).frame(width: 0, height: 0) }
        .overlay(alignment: .top) {
            if let toast {
                Button { if touch.archive.pending != nil { touch.showingSettings = true } } label: {
                    Text(toast).font(.subheadline).padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: .capsule)
                }.buttonStyle(.plain).padding(.top, 58).accessibilityIdentifier("touch.feedback")
            }
        }
        .onChange(of: touch.feedback) { _, value in
            guard let value else { return }
            toast = value; toastTask?.cancel()
            toastTask = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { toast = nil } }
        }
        .alert("请检查一下", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("知道了") { store.error = nil } } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase, initial: true) { _, phase in store.setForeground(phase == .active); if store.isShared { touch.setForeground(phase == .active) } }
    }
    private func navigation<Content: View>(tab: Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 4) {
                            if homeTouchVisible && store.activeTab == tab {
                                TouchBall(active: homeTouchActive).frame(width: 44, height: 44)
                            }
                            Text(store.content.trip.appName).font(.headline).foregroundStyle(TripStyle.green).fixedSize()
                        }
                    }.sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingSync = true } label: { SyncIndicator() }
                            .accessibilityLabel("共享同步，" + store.syncStatus)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .background(TripStyle.paper)
                .onAppear { visibleHomeTabs.insert(tab) }
                .onDisappear { visibleHomeTabs.remove(tab) }
        }
    }
}
