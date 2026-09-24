import SwiftUI

struct DestinationGuideList: View {
    var guides: [DestinationGuide]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "这一天，怎么玩", subtitle: "点开看完整攻略")
            ForEach(guides) { guide in
                NavigationLink { DestinationGuideView(guide: guide) } label: {
                    PaperCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "book.closed").foregroundStyle(TripStyle.green)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(guide.title).font(.headline).foregroundStyle(.primary)
                                Text(guide.summary).font(.subheadline).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
}

struct DestinationGuideView: View {
    var guide: DestinationGuide
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "游玩攻略")
                Text(guide.title).font(.system(.title, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                Text(guide.summary).font(.title3).foregroundStyle(.secondary)
                Text("资料核对：" + guide.updatedAt).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(guide.sections.enumerated()), id: \.offset) { _, section in
                    PaperCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(section.title).font(.headline).foregroundStyle(TripStyle.green)
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph).font(.body).lineSpacing(7).textSelection(.enabled)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                SectionTitle(title: "来源与最新信息")
                SourceLinks(links: guide.links)
            }.padding(22)
        }.background(TripStyle.paper).navigationTitle("游玩攻略").navigationBarTitleDisplayMode(.inline)
    }
}
