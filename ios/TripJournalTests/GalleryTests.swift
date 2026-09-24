import XCTest
import SwiftUI
@testable import TripJournal

@MainActor final class GalleryTests: XCTestCase {
    private func descendants<T: UIView>(_ root: UIView, of type: T.Type) -> [T] {
        (root as? T).map { [$0] } ?? root.subviews.flatMap { descendants($0, of: type) }
    }

    private final class BackPan: UIPanGestureRecognizer {
        var testVelocity = CGPoint(x: 200, y: 0)
        var testTranslation = CGPoint(x: 100, y: 0)
        override func velocity(in view: UIView?) -> CGPoint { testVelocity }
        override func translation(in view: UIView?) -> CGPoint { testTranslation }
        override var state: UIGestureRecognizer.State { get { .ended } set {} }
    }

    func testBackSwipeRequiresFirstPageAndUnzoomedHorizontalGesture() {
        let scroll = ZoomablePhoto.PhotoScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let coordinator = ZoomablePhoto.Coordinator()
        let photo = UIImageView(frame: scroll.bounds)
        scroll.addSubview(photo)
        coordinator.imageView = photo
        scroll.delegate = coordinator
        let pan = BackPan()
        scroll.backPan = pan
        scroll.maximumZoomScale = 6
        XCTAssertFalse(scroll.gestureRecognizerShouldBegin(pan))
        var dismissals = 0
        scroll.onSwipeBack = { dismissals += 1 }
        XCTAssertTrue(scroll.gestureRecognizerShouldBegin(pan))
        pan.testVelocity = CGPoint(x: -200, y: 0)
        XCTAssertFalse(scroll.gestureRecognizerShouldBegin(pan))
        pan.testVelocity = CGPoint(x: 50, y: 200)
        XCTAssertFalse(scroll.gestureRecognizerShouldBegin(pan))
        pan.testVelocity = CGPoint(x: 200, y: 0)
        scroll.zoomScale = 2
        XCTAssertFalse(scroll.gestureRecognizerShouldBegin(pan))
        scroll.handleBackPan(pan)
        XCTAssertEqual(dismissals, 0)
        scroll.zoomScale = 1
        pan.testTranslation.x = 30
        scroll.handleBackPan(pan)
        XCTAssertEqual(dismissals, 0)
        pan.testTranslation.x = 100
        scroll.handleBackPan(pan)
        XCTAssertEqual(dismissals, 1)
    }

    func testGalleryViewportIsCentered() async throws {
        let content = try ContentCatalog.load()
        let post = try XCTUnwrap(content.posts.first)
        let selection = GallerySelection(title: post.title, pages: post.images.map {
            GalleryPage(path: $0.path, caption: "第 \($0.order) 张原图", credit: post.author, source: post.url)
        }, index: 0)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ImageGallery(selection: selection))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .seconds(2))
        let scroll = try XCTUnwrap(descendants(host.view, of: ZoomablePhoto.PhotoScrollView.self).first)
        let photo = try XCTUnwrap(scroll.photo)
        let viewport = scroll.convert(scroll.bounds, to: window)
        let frame = photo.convert(photo.bounds, to: window)
        XCTAssertEqual(viewport.midX, window.bounds.midX, accuracy: 1)
        XCTAssertEqual(frame.midX, viewport.midX, accuracy: 1)
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot); attachment.name = "Gallery alignment"; attachment.lifetime = .keepAlways; add(attachment)
        try screenshot.pngData()?.write(to: URL(fileURLWithPath: "/tmp/trip-gallery.png"))
        let postWithBody = try XCTUnwrap(content.posts.first { $0.body != nil } ?? content.posts.first)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try TripStore(content: content, directory: directory, api: MemoryTripService(content.defaults), useKeychain: false)
        let detail = UIHostingController(rootView: NavigationStack { PostDetail(post: postWithBody) }.environment(store).tint(TripStyle.green))
        window.rootViewController = detail; detail.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let header = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let headerAttachment = XCTAttachment(image: header); headerAttachment.name = "Post title and original link"; headerAttachment.lifetime = .keepAlways; add(headerAttachment)
        try header.pngData()?.write(to: URL(fileURLWithPath: "/tmp/trip-post-header.png"))
    }
    func testPhotoRecentersWhenZoomingBelowFitSize() {
        let coordinator = ZoomablePhoto.Coordinator()
        let scroll = ZoomablePhoto.PhotoScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let photo = UIImageView(image: UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        })
        scroll.photo = photo; scroll.delegate = coordinator; coordinator.imageView = photo
        // Model the temporary undershoot while a pinch bounces below the fitted size.
        scroll.minimumZoomScale = 0.5; scroll.maximumZoomScale = 6
        scroll.addSubview(photo); scroll.layoutIfNeeded()
        scroll.setZoomScale(0.8, animated: false); scroll.layoutIfNeeded()
        let frame = photo.convert(photo.bounds, to: scroll)
        XCTAssertEqual(frame.midX, scroll.bounds.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, scroll.bounds.midY, accuracy: 1)
    }

    func testPhotoResizesForNewImageAndRecentersAfterZoom() {
        func image(_ size: CGSize) -> UIImage {
            UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            }
        }
        let coordinator = ZoomablePhoto.Coordinator()
        let scroll = ZoomablePhoto.PhotoScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        scroll.progressKey = "gallery-test-" + UUID().uuidString
        let photo = UIImageView(image: image(CGSize(width: 600, height: 400)))
        scroll.photo = photo; scroll.delegate = coordinator; coordinator.imageView = photo
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6
        scroll.addSubview(photo); scroll.layoutIfNeeded()
        scroll.setZoomScale(1.5, animated: false); scroll.layoutIfNeeded()
        XCTAssertEqual(photo.convert(photo.bounds, to: scroll).midY, scroll.bounds.midY, accuracy: 1)
        scroll.setZoomScale(1, animated: false); scroll.layoutIfNeeded()
        XCTAssertEqual(photo.convert(photo.bounds, to: scroll).midX, scroll.bounds.midX, accuracy: 1)
        XCTAssertEqual(photo.convert(photo.bounds, to: scroll).midY, scroll.bounds.midY, accuracy: 1)
        photo.image = image(CGSize(width: 600, height: 1800))
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        XCTAssertEqual(photo.bounds.height, 1170, accuracy: 1)
        XCTAssertEqual(scroll.contentSize.height, 1170, accuracy: 1)
        XCTAssertEqual(scroll.contentOffset.x, 0, accuracy: 1)
        scroll.frame.size = CGSize(width: 430, height: 700)
        scroll.setNeedsLayout(); scroll.layoutIfNeeded()
        XCTAssertEqual(photo.bounds.width, 430, accuracy: 1)
        XCTAssertEqual(photo.convert(photo.bounds, to: scroll).midX, scroll.bounds.midX, accuracy: 1)
    }

}
