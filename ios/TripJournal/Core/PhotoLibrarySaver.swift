import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

enum PhotoSaveError: LocalizedError, Equatable {
    case permissionDenied, unavailable, unreadable, writeFailed
    var errorDescription: String? {
        switch self {
        case .permissionDenied: "请在设置中允许添加照片，然后再保存。"
        case .unavailable: "这张图片尚未完整保存在本机，请先下载后重试。"
        case .unreadable: "暂时无法读取这张图片，请换一张重试。"
        case .writeFailed: "图片未能保存，请检查相册与设备剩余空间后重试。"
        }
    }
}

actor PhotoLibrarySaver {
    static let shared = PhotoLibrarySaver()

    /// Preserve JPEG/PNG bytes. Convert unsupported source formats at their full pixel size.
    static func photoData(at url: URL) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { throw PhotoSaveError.unavailable }
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { throw PhotoSaveError.unreadable }
        if type as String == UTType.jpeg.identifier || type as String == UTType.png.identifier { return data }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PhotoSaveError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw PhotoSaveError.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw PhotoSaveError.unreadable }
        return output as Data
    }

    func save(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw PhotoSaveError.unavailable }
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined { authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
        guard authorization == .authorized || authorization == .limited else { throw PhotoSaveError.permissionDenied }
        let data = try Self.photoData(at: url)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch { throw PhotoSaveError.writeFailed }
    }
}
