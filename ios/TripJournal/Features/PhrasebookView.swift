import SwiftUI
import AVFoundation

struct PhrasebookView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = PhraseSpeechPlayer()
    @State private var query = ""
    @State private var selectedSection: String?
    private var results: [PhraseSection] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.content.phrases.compactMap { section in
            guard !term.isEmpty || selectedSection == nil || selectedSection == section.id else { return nil }
            let phrases = section.items.filter {
                term.isEmpty || [section.title, $0.native, $0.local, $0.note ?? ""].contains { $0.localizedStandardContains(term) }
            }
            return phrases.isEmpty ? nil : PhraseSection(id: section.id, title: section.title, items: phrases)
        }
    }

    private func phraseRow(_ phrase: Phrase) -> some View {
        Button {
            player.toggle(phrase)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(phrase.native).font(.subheadline).foregroundStyle(.secondary)
                    Text(phrase.local).font(.title3.weight(.medium)).foregroundStyle(TripStyle.green)
                    if let note = phrase.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: player.playingPhraseID == phrase.id ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(TripStyle.green)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(phrase.native)，\(phrase.local)")
        .accessibilityValue(player.playingPhraseID == phrase.id ? "正在朗读" : "未播放")
        .accessibilityHint(player.playingPhraseID == phrase.id ? "轻点停止朗读" : "轻点朗读" + TripConfig.current.speech.label)
        .contextMenu {
            Button("复制" + TripConfig.current.speech.label, systemImage: "doc.on.doc") { UIPasteboard.general.string = phrase.local }
            Button("复制中文", systemImage: "doc.on.doc") { UIPasteboard.general.string = phrase.native }
        }
        .listRowBackground(TripStyle.card)
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    Text("先找中文，再照着说。短句就够用，地名也可以直接给对方看。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("点击整行朗读 · 再点停止 · 长按可复制 · 右上角选场景")
                        .font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(TripStyle.card)
            }
            ForEach(results) { section in
                Section(section.title) {
                    ForEach(section.items) { phrase in
                        phraseRow(phrase)
                    }
                }
            }
        }
        .overlay { if results.isEmpty { ContentUnavailableView.search(text: query) } }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜中文或\(TripConfig.current.speech.label)短句")
        .scrollContentBackground(.hidden)
        .background(TripStyle.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("全部场景") { selectedSection = nil; query = "" }
                    ForEach(store.content.phrases) { section in
                        Button(section.title) { selectedSection = section.id; query = "" }
                    }
                } label: { Label("选择场景", systemImage: "line.3.horizontal.decrease") }
            }
        }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { player.stop() } }
        .onChange(of: query) { _, _ in player.stop() }
        .onChange(of: selectedSection) { _, _ in player.stop() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in player.stop() }
        .alert("无法朗读", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("好", role: .cancel) { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
        .navigationTitle("旅行短句 · " + TripConfig.current.speech.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
