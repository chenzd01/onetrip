import SwiftUI
import Observation

@MainActor @Observable
final class PhotoSaveController {
    var isSaving = false
    var saved = false
    var error: String?
    var needsSettings = false

    func save(path: String) {
        save { guard let url = ContentCatalog.resource(path) else { throw PhotoSaveError.unavailable }; return url }
    }

    func save(resolveURL: @escaping @Sendable () async throws -> URL) {
        guard !isSaving else { return }
        isSaving = true; saved = false
        Task {
            defer { isSaving = false }
            do {
                let url = try await resolveURL()
                try await PhotoLibrarySaver.shared.save(url: url)
                saved = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                UIAccessibility.post(notification: .announcement, argument: "已保存到相册")
                try? await Task.sleep(for: .seconds(2))
                saved = false
            } catch {
                needsSettings = (error as? PhotoSaveError) == .permissionDenied
                self.error = error.localizedDescription
            }
        }
    }
}

private struct PhotoSaveFeedback: ViewModifier {
    @Bindable var saver: PhotoSaveController
    @Environment(\.openURL) private var openURL
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if saver.saved || saver.isSaving {
                    Label(saver.saved ? "已保存到相册" : "正在保存图片…", systemImage: saver.saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.regularMaterial, in: .capsule).padding(12).allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .alert("无法保存图片", isPresented: Binding(get: { saver.error != nil }, set: { if !$0 { saver.error = nil } })) {
                if saver.needsSettings {
                    Button("前往设置") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                }
                Button("知道了", role: .cancel) { saver.error = nil }
            } message: { Text(saver.error ?? "") }
    }
}

private struct SavePhotoOnLongPress: ViewModifier {
    var path: String?
    @State private var saver = PhotoSaveController()
    func body(content: Content) -> some View {
        if let path {
            content
                .contextMenu {
                    Button("保存到相册", systemImage: "square.and.arrow.down") { saver.save(path: path) }.disabled(saver.isSaving)
                }
                .accessibilityAction(named: "保存到相册") { saver.save(path: path) }
                .photoSaveFeedback(saver)
        } else { content }
    }
}

extension View {
    func photoSaveFeedback(_ saver: PhotoSaveController) -> some View { modifier(PhotoSaveFeedback(saver: saver)) }
    func savePhotoOnLongPress(path: String?) -> some View { modifier(SavePhotoOnLongPress(path: path)) }
}
