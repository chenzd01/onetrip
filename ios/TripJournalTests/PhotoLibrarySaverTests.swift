import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import TripJournal

final class PhotoLibrarySaverTests: XCTestCase {
    func testJPEGAndPNGKeepOriginalBytes() throws {
        for type in [UTType.jpeg, .png] {
            let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            let data = try makeImage(type: type, width: 31, height: 207)
            try data.write(to: url)
            XCTAssertEqual(try PhotoLibrarySaver.photoData(at: url), data)
        }
    }

    func testOtherImageFormatsConvertToPNGWithoutResizing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try makeImage(type: .tiff, width: 47, height: 5001).write(to: url)
        let result = try PhotoLibrarySaver.photoData(at: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 47)
        XCTAssertEqual(image.height, 5001)
    }

    func testLongestBundledPostImageSavesAtOriginalSize() throws {
        let catalog = try ContentCatalog.load()
        let images = catalog.posts.flatMap(\.images)
        let path = try XCTUnwrap((images.filter { $0.path.hasSuffix(".webp") }.max { $0.height < $1.height } ?? images.max { $0.height < $1.height })?.path)
        let url = try XCTUnwrap(ContentCatalog.resource(path))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let original = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let result = try PhotoLibrarySaver.photoData(at: url)
        let savedSource = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        if [UTType.jpeg.identifier, UTType.png.identifier].contains(CGImageSourceGetType(source) as String? ?? "") {
            XCTAssertEqual(result, try Data(contentsOf: url))
        } else {
            XCTAssertEqual(CGImageSourceGetType(savedSource) as String?, UTType.png.identifier)
        }
        let saved = try XCTUnwrap(CGImageSourceCreateImageAtIndex(savedSource, 0, nil))
        XCTAssertEqual(saved.width, original.width)
        XCTAssertEqual(saved.height, original.height)
    }

    func testConversionPreservesOrientationMetadata() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        // EXIF 6 rotates the stored pixel grid clockwise for correct display.
        let data = try makeImage(type: .tiff, width: 31, height: 207, orientation: 6)
        try data.write(to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let originalProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(originalProperties[kCGImagePropertyOrientation] as? Int, 6)
        let result = try PhotoLibrarySaver.photoData(at: url)
        let savedSource = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        let savedProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(savedSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(savedProperties[kCGImagePropertyOrientation] as? Int, 6)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(savedSource, 0, nil))
        XCTAssertEqual(image.width, 31)
        XCTAssertEqual(image.height, 207)
    }

    func testMissingAndInvalidImagesFailBeforePhotoCreation() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        XCTAssertThrowsError(try PhotoLibrarySaver.photoData(at: url)) { XCTAssertEqual($0 as? PhotoSaveError, .unavailable) }
        try Data("not an image".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try PhotoLibrarySaver.photoData(at: url)) { XCTAssertEqual($0 as? PhotoSaveError, .unreadable) }
    }

    private func makeImage(type: UTType, width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
