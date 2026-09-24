import SwiftUI

struct GalleryPage: Identifiable {
    var path: String
    var caption: String
    var credit: String
    var source: String?
    var zoomProgressKey: String? = nil
    var id: String { path }
    init(photo: Photo) { path = photo.path; caption = photo.caption; credit = photo.creator + " · " + photo.license; source = photo.sourceUrl }
    init(path: String, caption: String, credit: String, source: String? = nil, zoomProgressKey: String? = nil) { self.path = path; self.caption = caption; self.credit = credit; self.source = source; self.zoomProgressKey = zoomProgressKey }
}
struct GallerySelection: Identifiable {
    var id = UUID()
    var title: String
    var pages: [GalleryPage]
    var index: Int
}
struct ImageGallery: View {
    @Environment(\.dismiss) private var dismiss
    let selection: GallerySelection
    @State private var index: Int
    @State private var photoSaver = PhotoSaveController()
    init(selection: GallerySelection) {
        self.selection = selection
        _index = State(initialValue: min(max(0, selection.index), max(0, selection.pages.count - 1)))
    }
    private var currentPage: GalleryPage? { selection.pages.indices.contains(index) ? selection.pages[index] : nil }
    var body: some View {
        NavigationStack {
            Group {
                if selection.pages.isEmpty {
                    ContentUnavailableView("暂无图片", systemImage: "photo", description: Text("这里还没有可查看的图片。"))
                } else {
                    TabView(selection: $index) {
                        ForEach(Array(selection.pages.enumerated()), id: \.element.id) { i, page in
                            GalleryImage(page: page, nearby: abs(i - index) <= 1, photoSaver: photoSaver, onSwipeBack: i == 0 && index == 0 ? { dismiss() } : nil)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).tag(i)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never)).background(.black)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let page = currentPage {
                    VStack(spacing: 8) {
                        HStack { Button("上一张", systemImage: "chevron.left") { index = max(0,index-1) }.labelStyle(.iconOnly).disabled(index == 0); Text("\(index+1) / \(selection.pages.count)").monospacedDigit(); Spacer(); Text("双指缩放 · 双击放大").foregroundStyle(.secondary); Button("下一张", systemImage: "chevron.right") { index = min(selection.pages.count-1,index+1) }.labelStyle(.iconOnly).disabled(index == selection.pages.count-1) }.font(.caption)
                        Text(page.caption).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        HStack { Text(page.credit).font(.caption2).foregroundStyle(.secondary); Spacer(); if let s = page.source, let u = URL(string: s) { Link("来源 ↗", destination: u).font(.caption) } }
                    }.padding(18).background(.ultraThinMaterial)
                }
            }
            .navigationTitle(selection.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let page = currentPage { Button("保存到相册", systemImage: "square.and.arrow.down") { photoSaver.save(path: page.path) }.disabled(photoSaver.isSaving) }
                }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }.preferredColorScheme(.dark).photoSaveFeedback(photoSaver)
    }
}
struct GalleryImage: View {
    var page: GalleryPage
    var nearby: Bool
    var photoSaver: PhotoSaveController
    var onSwipeBack: (() -> Void)? = nil
    @State private var image: UIImage?
    var body: some View {
        ZStack {
            Color.black
            if let image { ZoomablePhoto(image: image, progressKey: page.zoomProgressKey ?? ("image-offset-" + page.path), onSwipeBack: onSwipeBack) }
            else { ProgressView().tint(.white) }
        }
        // Keep both sides of a swipe alive until the page transition is complete.
        .task(id: nearby) {
            if nearby {
                let loaded = await ImageRepository.shared.image(path: page.path, pixelSize: 4096)
                if !Task.isCancelled { image = loaded }
            } else { image = nil }
        }
        .accessibilityLabel(page.caption)
        .contextMenu {
            Button("保存到相册", systemImage: "square.and.arrow.down") { photoSaver.save(path: page.path) }.disabled(photoSaver.isSaving)
        }
        .accessibilityAction(named: "保存到相册") { photoSaver.save(path: page.path) }
    }
}
struct ZoomablePhoto: UIViewRepresentable {
    var image: UIImage
    var progressKey: String
    var onSwipeBack: (() -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = PhotoScrollView(); scroll.delegate = context.coordinator; scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6
        scroll.backgroundColor = .black; scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        let view = UIImageView(); view.contentMode = .scaleAspectFit; scroll.addSubview(view)
        context.coordinator.imageView = view
        context.coordinator.progressKey = progressKey
        scroll.photo = view; scroll.progressKey = progressKey
        scroll.onSwipeBack = onSwipeBack
        let backPan = UIPanGestureRecognizer(target: scroll, action: #selector(PhotoScrollView.handleBackPan(_:)))
        backPan.maximumNumberOfTouches = 1
        backPan.delegate = scroll
        scroll.backPan = backPan
        scroll.addGestureRecognizer(backPan)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:))); doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        (scroll as? PhotoScrollView)?.onSwipeBack = onSwipeBack
        let view = context.coordinator.imageView!
        if view.image !== image { scroll.setZoomScale(1, animated: false); view.image = image }
        scroll.setNeedsLayout()
    }
    final class PhotoScrollView: UIScrollView, UIGestureRecognizerDelegate {
        var onSwipeBack: (() -> Void)?
        var backPan: UIPanGestureRecognizer?

        @objc func handleBackPan(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .ended, zoomScale <= minimumZoomScale else { return }
            let distance = gesture.translation(in: self)
            if distance.x >= 80 && distance.x > abs(distance.y) * 1.5 { onSwipeBack?() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === backPan && otherGestureRecognizer is UIPanGestureRecognizer
        }
        weak var photo: UIImageView?
        var progressKey = ""
        private var lastSize = CGSize.zero
        private weak var lastImage: UIImage?
        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 0, bounds.height > 0, let photo, let image = photo.image else { return }
            if bounds.size != lastSize || image !== lastImage {
                lastSize = bounds.size; lastImage = image
                setZoomScale(1, animated: false)
                let height = image.size.height / image.size.width * bounds.width
                photo.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
                contentSize = photo.bounds.size
                let fraction = UserDefaults.standard.double(forKey: progressKey)
                contentOffset = CGPoint(x: 0, y: max(0, contentSize.height - bounds.height) * min(1, max(0, fraction)))
            }
            centerPhoto()
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === backPan {
                let velocity = backPan?.velocity(in: self) ?? .zero
                return onSwipeBack != nil && zoomScale <= minimumZoomScale
                    && velocity.x > 0 && velocity.x > abs(velocity.y) * 1.5
            }
            if gestureRecognizer === panGestureRecognizer && zoomScale <= minimumZoomScale {
                let velocity = panGestureRecognizer.velocity(in: self)
                if abs(velocity.x) > abs(velocity.y) { return false }
            }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        func centerPhoto() {
            guard let photo else { return }
            // Center the zoomed image in each axis that does not need scrolling.
            photo.center = CGPoint(x: max(bounds.width, contentSize.width) / 2,
                                   y: max(bounds.height, contentSize.height) / 2)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?
        var progressKey = ""
        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { saveOffset(scrollView) } }
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { saveOffset(scrollView) }
        private func saveOffset(_ scroll: UIScrollView) {
            guard scroll.zoomScale == 1 else { return }
            let maximum = scroll.contentSize.height - scroll.bounds.height
            if maximum > 0 { UserDefaults.standard.set(min(1,max(0,scroll.contentOffset.y/maximum)),forKey:progressKey) }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? PhotoScrollView)?.centerPhoto()
        }
        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView, let imageView else { return }
            if scroll.zoomScale > 1 { scroll.setZoomScale(1, animated: !UIAccessibility.isReduceMotionEnabled) }
            else { let p = gesture.location(in: imageView); let size = CGSize(width: scroll.bounds.width/2.5, height: scroll.bounds.height/2.5); scroll.zoom(to: CGRect(x: p.x-size.width/2, y: p.y-size.height/2, width: size.width, height: size.height), animated: !UIAccessibility.isReduceMotionEnabled) }
        }
    }
}
struct PostDetail: View {
    @Environment(TripStore.self) private var store
    var post: Post
    @State private var gallery: GallerySelection?
    @State private var favorite = false
    @AppStorage("post-favorites-revision") private var favoritesRevision = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(post.title).font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let url = URL(string: post.url) {
                    Link(destination: url) { Label(post.platformName + "原文链接", systemImage: "arrow.up.right.square").frame(minHeight: 44) }
                }
                Eyebrow(text: post.categories.joined(separator: " · "))
                Text("\(post.author) · \(post.date)").font(.subheadline).foregroundStyle(.secondary)
                if let summary = post.summary {
                    SectionTitle(title: "适合我们的要点", subtitle: "根据原帖整理")
                    Text(summary).font(.body).textSelection(.enabled)
                }
                HStack { Label("\(post.images.count) 张原图已离线", systemImage: "checkmark.circle"); Spacer(); Button { favorite.toggle(); favoritesRevision += 1; UserDefaults.standard.set(favorite, forKey: "post-favorite-"+post.id) } label: { Image(systemName: favorite ? "bookmark.fill" : "bookmark") }.accessibilityLabel(favorite ? "取消收藏" : "收藏攻略") }.font(.caption)
                VStack(alignment: .leading, spacing: 12) {
                    Text("原帖正文").font(.headline).foregroundStyle(TripStyle.green)
                    if let body = post.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(body).font(.body).lineSpacing(6).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("这篇的文字正文尚未收录，可通过顶部链接查看原帖。").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                let related = (post.guidePlaces ?? []).compactMap { store.place($0) }.filter(\.isDining)
                if !related.isEmpty {
                    Text("这篇提到的餐饮").font(.headline).foregroundStyle(TripStyle.green)
                    ForEach(related) { place in NavigationLink { DiningDetail(place: place) } label: { Label(place.name, systemImage: "fork.knife").frame(minHeight: 44) } }
                }
                Text("原帖图片").font(.headline).foregroundStyle(TripStyle.green)
                LazyVStack(spacing: 16) {
                    ForEach(Array(post.images.enumerated()), id: \.offset) { index, image in
                        Button { open(at: index) } label: {
                            LocalPhoto(path: image.path, height: min(520, CGFloat(image.height) / CGFloat(image.width) * 330), pixelSize: 1100, allowsPhotoSaving: false)
                                .overlay(alignment: .bottomTrailing) { Text("\(index+1)/\(post.images.count)").font(.caption).padding(8).background(.regularMaterial, in: .capsule).padding(10) }
                                .clipShape(.rect(cornerRadius: 20))
                        }.buttonStyle(.plain).accessibilityLabel("打开第 \(index+1) 张原图")
                            .savePhotoOnLongPress(path: image.path)
                    }
                }
                Text("原作者内容 · 采集于 \(post.capturedAt)\n\(post.heat)（采集快照）").font(.caption).foregroundStyle(.secondary)
            }.padding(22)
        }.background(TripStyle.paper).navigationTitle("旅行阅读").navigationBarTitleDisplayMode(.inline)
        .onAppear { favorite = UserDefaults.standard.bool(forKey: "post-favorite-"+post.id) }
        .fullScreenCover(item: $gallery) { ImageGallery(selection: $0) }
    }
    private func open(at index: Int) {
        guard post.images.indices.contains(index) else { return }
        gallery = .init(title: post.title, pages: post.images.map { .init(path: $0.path, caption: "第 \($0.order) 张原图", credit: post.author, source: post.url) }, index: index)
    }
}
