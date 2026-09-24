import SwiftUI
import ImageIO

enum TripStyle {
    static let green = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.67, green: 0.82, blue: 0.68, alpha: 1) : UIColor(red: 0.16, green: 0.31, blue: 0.26, alpha: 1) })
    static let coral = Color(red: 0.76, green: 0.36, blue: 0.26)
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.08, green: 0.10, blue: 0.09, alpha: 1) : UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .secondarySystemBackground : UIColor(red: 1, green: 0.995, blue: 0.98, alpha: 1) })
}
struct PaperCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(TripStyle.card, in: .rect(cornerRadius: 24)) }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(text).font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(TripStyle.green) }
}
struct SectionTitle: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title2.weight(.semibold)).foregroundStyle(TripStyle.green)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
actor ImageRepository {
    static let shared = ImageRepository()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.totalCostLimit = 45 * 1024 * 1024 }
    func image(path: String, pixelSize: Int) -> UIImage? {
        let key = "\(path)-\(pixelSize)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let url = ContentCatalog.resource(path), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixelSize, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg); cache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height); return image
    }
}
struct LocalPhoto: View {
    var path: String?
    var height: CGFloat = 200
    var pixelSize = 1000
    var originalPath: String? = nil
    var allowsPhotoSaving = true
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() }
                else { Rectangle().fill(TripStyle.green.opacity(0.08)).overlay { Image(systemName: "leaf").foregroundStyle(TripStyle.green.opacity(0.3)) } }
            }.frame(width: geometry.size.width, height: height).clipped()
        }
        .frame(height: height)
        .task(id: path) { image = nil; if let path { let loaded = await ImageRepository.shared.image(path: path, pixelSize: pixelSize); if !Task.isCancelled { image = loaded } } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("图片")
        .accessibilityHidden(!allowsPhotoSaving || path == nil)
        .savePhotoOnLongPress(path: allowsPhotoSaving ? (originalPath ?? path) : nil)
    }
}
struct SourceLinks: View {
    var links: [SourceLink]
    var body: some View {
        ForEach(links, id: \.self) { link in
            if let url = URL(string: link.url), ["https", "http"].contains(url.scheme ?? "") { Link(destination: url) { Label(link.label, systemImage: "arrow.up.right") }.font(.subheadline) }
        }
    }
}
