import SwiftUI

struct AboutView: View {
    @Environment(TripStore.self) private var store
    var body: some View {
        List {
            Section("关于这次旅行") {
                Text(store.content.trip.appName).font(.system(.title,design:.serif,weight:.semibold)).foregroundStyle(TripStyle.green)
                Text("\(store.content.trip.destination.name) · \(store.content.trip.startDate) – \(store.content.trip.endDate) · \(store.content.trip.dayCount) 天\n原生旅行手帐，留一点空白给路上的惊喜。")
                LabeledContent("版本",value:(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.0") + " (" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "1") + ")")
            }
            Section("隐私与数据") {
                Text("不含广告或行为分析，不进行跨 App 跟踪。内置攻略与照片可直接离线阅读。")
                if store.isShared {
                    Text("安装此版本的使用者默认共享同一份行程、清单、预算、住宿和票券，无需登录。附件原件只在你导入或同步时传输。")
                    Text("共享连接自动建立和续期；连接凭证存放在系统钥匙串。攻略收藏、阅读位置和提醒设置只保存在这部手机。")
                } else {
                    Text("此版本未配置共享后端：行程、清单、预算、住宿、票券、攻略收藏和提醒设置都只保存在这部手机，不会上传。")
                }
                Text("地图和外部来源链接会连接 Apple 或对应网站。导航无需向本 App 提供实时位置。")
                Text("已保存的旅行资料可离线使用。删除共享资料会同步影响旅行同伴；卸载 App 会移除本机副本。")
            }
            Section("内容与照片来源") {
                Text("攻略在详情页保留作者、来源、采集日期及原图顺序。酒店详情保留报价核对日期与预订来源。")
                NavigationLink("实景照片署名与许可") { PhotoCreditsView() }
                ForEach(store.content.hotels.hotels) { hotel in
                    if let url = URL(string:hotel.photo.source) { Link(hotel.name + " · 酒店图片来源",destination:url).font(.subheadline) }
                }
            }
            Section("地图定位与内容来源") {
                Text("内置地点坐标与资料的来源和许可如下。区域坐标用于查看位置，具体入口以地点说明及现场为准。")
                ForEach(store.content.trip.attributions, id: \.self) { source in
                    if let url = URL(string: source.url) { Link(source.label, destination: url) } else { Text(source.label) }
                }
                if let url = ContentCatalog.resource("place-locations.json") { ShareLink("导出地点坐标与来源", item: url) }
            }
        }.navigationTitle("关于这本旅行手帐").navigationBarTitleDisplayMode(.inline)
    }
}
struct PhotoCreditsView: View {
    @Environment(TripStore.self) private var store
    var body: some View {
        List {
            ForEach(store.content.photos.keys.sorted(),id:\.self) { key in
                Section(store.place(key)?.name ?? key) {
                    ForEach(store.content.photos[key]?.photos ?? []) { photo in
                        VStack(alignment:.leading,spacing:7) {
                            Text(photo.caption).font(.headline)
                            Text(photo.creator + " · " + photo.license).font(.caption).foregroundStyle(.secondary)
                            if let url = URL(string:photo.sourceUrl) { Link("原始来源",destination:url) }
                            if let url = URL(string:photo.licenseUrl), !photo.licenseUrl.isEmpty { Link("许可说明",destination:url) }
                        }
                    }
                }
            }
        }.navigationTitle("照片署名").navigationBarTitleDisplayMode(.inline)
    }
}
