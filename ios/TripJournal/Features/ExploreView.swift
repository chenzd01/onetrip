import SwiftUI
import MapKit

struct ExploreView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TripStore.self) private var store
    @State private var section = 0
    @State private var searches: [Int: String] = [:]
    @State private var diningFilters = DiningFilters()
    @State private var guideTopic = "全部"
    @State private var kind = "全部"
    @State private var favoritesOnly = false
    @State private var comparison = false
    private var placeFavorites: PlaceFavorites { .shared }
    private var filteredPlaces: [Place] {
        ordinaryPlaces.filter { (kind == "全部" || $0.kind == kind) && (!favoritesOnly || placeFavorites.contains($0.id)) && matches($0.name + $0.en + $0.zone) }
    }
    @AppStorage("post-favorites-revision") private var readingRevision = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionTitle(title: section == 1 ? "好好吃饭，慢慢选" : "喜欢的地方，慢慢发现", subtitle: section == 1 ? "小吃日常 · 一两餐特别体验" : "城市风景 · 好好吃饭 · 私藏攻略 · 住得舒服")
                Picker("探索内容", selection: $section) { Text("地点").tag(0); Text("餐饮").tag(1); Text("攻略").tag(2); Text("酒店").tag(3) }.pickerStyle(.segmented)
                if section == 0 {
                    HStack {
                        Eyebrow(text: "PLACES TO FALL IN LOVE WITH")
                        Spacer()
                        Menu { Button("全部") { kind = "全部" }; ForEach(Array(Set(ordinaryPlaces.map(\.kind))).sorted(), id: \.self) { k in Button(k) { kind = k } } } label: { Label(kind, systemImage: "line.3.horizontal.decrease").font(.caption) }
                    }
                    Toggle("只看本机收藏的地点", isOn: $favoritesOnly)
                    if filteredPlaces.isEmpty {
                        ContentUnavailableView {
                            Label(favoritesOnly && !ordinaryPlaces.contains(where: { placeFavorites.contains($0.id) }) ? "还没有收藏地点" : "没有符合条件的地点", systemImage: favoritesOnly ? "heart" : "magnifyingglass")
                        } description: {
                            Text(favoritesOnly && !ordinaryPlaces.contains(where: { placeFavorites.contains($0.id) }) ? "轻点地点卡片上的爱心，把想去的地方先留下来。" : "试试其他关键词，或调整分类和收藏筛选。")
                        } actions: {
                            Button("查看全部地点") { searches[section] = ""; kind = "全部"; favoritesOnly = false }
                        }
                    }
                    LazyVStack(spacing: 22) {
                        ForEach(filteredPlaces) { place in
                            NavigationLink { PlaceDetail(place: place) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    LocalPhoto(path: store.album(place.id)?.photos.first?.path, height: 210, allowsPhotoSaving: false).overlay(alignment: .topLeading) { Text(place.zone).font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8).background(.regularMaterial, in: .capsule).padding(14) }
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack { Text(place.name).font(.title3.weight(.semibold)); Spacer(); Image(systemName: "arrow.up.right").font(.subheadline) }
                                        Text(place.desc).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                        HStack { Text(place.kind); Text("·"); Text("建议 \(place.hours, specifier: "%.1f") 小时") }.font(.caption).foregroundStyle(.secondary)
                                    }.padding(20)
                                }.background(TripStyle.card).clipShape(.rect(cornerRadius: 24))
                            }.buttonStyle(.plain)
                            .accessibilityIdentifier("explore.place")
                            .savePhotoOnLongPress(path: store.album(place.id)?.photos.first?.path)
                            .overlay(alignment: .topTrailing) { PlaceFavoriteButton(place: place).padding(14) }
                        }
                    }
                } else if section == 1 {
                    DiningListView(search: search, filters: $diningFilters)
                } else if section == 2 {
                    Eyebrow(text: "TRAVEL STORIES · READ AT YOUR PACE")
                    Picker("攻略主题", selection: $guideTopic) {
                        Text("全部").tag("全部")
                        Text("餐饮").tag("餐饮")
                    }.pickerStyle(.segmented)
                    Toggle("只看本机收藏的攻略", isOn: $favoritesOnly)
                    if !favoritesOnly { DiningGuideListView(search: search) }
                    LazyVStack(spacing: 20) {
                        ForEach(filteredPosts) { post in
                            NavigationLink { PostDetail(post: post) } label: {
                                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
                                    LocalPhoto(path: post.thumb, height: 142, pixelSize: 500, originalPath: post.images.first?.path, allowsPhotoSaving: false).frame(width: typeSize.isAccessibilitySize ? nil : 115).clipShape(.rect(cornerRadius: 17))
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(post.categories.joined(separator: " · ")).font(.caption2).foregroundStyle(TripStyle.coral)
                                        Text(post.title).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                                        Spacer(minLength: 0)
                                        Text(post.author).font(.caption).foregroundStyle(.secondary)
                                        Text("\(post.images.count) 张原图 · 已离线").font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 142)
                                }.padding(14).background(TripStyle.card, in: .rect(cornerRadius: 24))
                            }.buttonStyle(.plain)
                            .savePhotoOnLongPress(path: post.images.first?.path)
                        }
                    }
                } else {
                    Eyebrow(text: "A PLACE TO COME HOME TO")
                    Toggle("只看收藏的酒店", isOn: $favoritesOnly)
                    Button("比较酒店", systemImage: "rectangle.split.3x1") { comparison = true }.buttonStyle(.glass)
                    LazyVStack(spacing: 22) {
                        ForEach(store.content.hotels.hotels.filter { (!favoritesOnly || (store.plan.hotelFavorites ?? []).contains($0.id)) && matches($0.name + $0.en + $0.region) }) { hotel in
                            NavigationLink { HotelDetail(hotel: hotel) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    LocalPhoto(path: hotel.photo.path, height: 205, allowsPhotoSaving: false)
                                    VStack(alignment: .leading, spacing: 9) {
                                        Text(hotel.name).font(.title3.weight(.semibold))
                                        Text(hotel.reason).font(.subheadline).foregroundStyle(.secondary)
                                        HStack { Label(hotel.region, systemImage: "mappin"); Spacer(); if (store.plan.hotelFavorites ?? []).contains(hotel.id) { Image(systemName: "heart.fill").foregroundStyle(TripStyle.coral) } }.font(.caption)
                                        Text("报价核对于 \(hotel.checkedAt)").font(.caption2).foregroundStyle(.secondary)
                                    }.padding(20)
                                }.background(TripStyle.card).clipShape(.rect(cornerRadius: 24))
                            }.buttonStyle(.plain)
                            .savePhotoOnLongPress(path: hotel.photo.path)
                        }
                    }
                }
            }.padding(22)
        }.background(TripStyle.paper).searchable(text: Binding(get: { search }, set: { searches[section] = $0 }), prompt: ["搜索地点、区域", "搜索餐厅、菜系、区域", "搜索攻略、作者", "搜索酒店、区域"][section])
        .onChange(of: section) { favoritesOnly = false }
        .sheet(isPresented: $comparison) { NavigationStack { HotelCompareView() } }
    }
    private var search: String { searches[section] ?? "" }
    private var filteredPosts: [Post] {
        store.content.posts.filter { post in
            let isDiningGuide = (post.guidePlaces ?? []).contains { store.content.dining?.venue($0) != nil }
                || post.categories.contains { $0.contains("餐饮") || $0.contains("美食") }
            return (!favoritesOnly || isPostFavorite(post.id)) && (guideTopic == "全部" || isDiningGuide)
                && matches(post.title + post.author + post.categories.joined())
        }
    }
    private var ordinaryPlaces: [Place] {
        store.allPlaces.filter { !$0.isDining }
    }
    private func isPostFavorite(_ id: String) -> Bool { _ = readingRevision; return UserDefaults.standard.bool(forKey: "post-favorite-" + id) }
    private func matches(_ text: String) -> Bool { search.isEmpty || text.localizedStandardContains(search) }
}
struct PlaceDetail: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TripStore.self) private var store
    var place: Place
    @State private var gallery: GallerySelection?
    @State private var addingPlace: Place?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let album = store.album(place.id) {
                    Button { gallery = .init(title: place.name, pages: album.photos.map(GalleryPage.init), index: 0) } label: {
                        LocalPhoto(path: album.photos.first?.path, height: 310, pixelSize: 1400, allowsPhotoSaving: false)
                            .overlay(alignment: .bottomTrailing) { Label("\(album.photos.count) 张实景", systemImage: "photo.on.rectangle").font(.caption.weight(.medium)).padding(10).background(.regularMaterial, in: .capsule).padding(18) }
                    }.buttonStyle(.plain)
                    .savePhotoOnLongPress(path: album.photos.first?.path)
                }
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: place.en.uppercased())
                        Text(place.name).font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                        Text(place.desc).font(.title3).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    HStack { Label(place.zone, systemImage: "mappin"); Spacer(); Label("\(place.hours, specifier: "%.1f") 小时", systemImage: "clock") }.font(.subheadline).foregroundStyle(TripStyle.green)
                    PaperCard {
                        VStack(alignment: .leading, spacing: 18) {
                            detail("什么时候去", text: place.bestTime ?? "按当天节奏安排", icon: "sun.max")
                            detail("开放时间", text: place.opening ?? "请核对来源", icon: "clock")
                            detail("费用参考", text: place.price ?? "\(store.content.trip.currency.localSymbol)\(Int(place.budget)) / 人", icon: "ticket")
                        }
                    }
                    detail("小小提醒", text: place.tip, icon: "sparkles")
                    detail("怎么到这里", text: place.travel, icon: "tram")
                    if let location = store.content.locations[place.id] {
                        Text("地图定位：" + location.name).font(.caption).foregroundStyle(.secondary)
                    }
                    detail("附近吃什么", text: place.food, icon: "fork.knife")
                    detail("下雨也从容", text: place.rain, icon: "cloud.rain")
                    NavigationLink { TicketListView(place: place) } label: { PaperCard { HStack { Label("这里的门票", systemImage: "ticket"); Spacer(); Text("\((store.plan.tickets?[place.id] ?? []).count) 条").foregroundStyle(.secondary); Image(systemName: "chevron.right") } } }.buttonStyle(.plain)
                    if let guides = place.guides, !guides.isEmpty {
                        DestinationGuideList(guides: guides)
                    }
                    let related = store.content.posts.filter { $0.id == place.id || $0.id.hasPrefix(place.id + "-") }
                    if !related.isEmpty {
                        SectionTitle(title: "相关攻略", subtitle: "旅行者的实地分享 · 原图已离线")
                        ForEach(related) { post in
                            NavigationLink { PostDetail(post: post) } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: PlaceSource.xiaohongshu.icon).foregroundStyle(TripStyle.coral)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(post.title).font(.subheadline).foregroundStyle(.primary)
                                        Text(post.platformName + " · " + post.author).font(.caption).foregroundStyle(TripStyle.coral)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(16).background(TripStyle.coral.opacity(0.07), in: .rect(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                    if let url = URL(string: place.link), !place.link.isEmpty { PlaceSourceLink(url: url) }
                    let location = store.content.locations[place.id]
                    DestinationMapButton(query: location?.address ?? (place.en.isEmpty ? place.name : place.en), name: location?.name ?? place.name, coordinates: location?.coordinates, showsPreview: true)
                        .buttonStyle(.plain)
                }.padding(.horizontal, 22).padding(.bottom, 22)
            }
        }.background(TripStyle.paper).navigationTitle(place.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                let location = store.content.locations[place.id]
                DestinationMapButton(query: location?.address ?? (place.en.isEmpty ? place.name : place.en), name: location?.name ?? place.name, coordinates: location?.coordinates).buttonStyle(.glass)
                Button { addingPlace = place } label: { Label("放进行程", systemImage: "plus").frame(maxWidth: .infinity).padding(6) }.buttonStyle(.glassProminent)
            }.padding(.horizontal, 22).padding(.vertical, 10)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { PlaceFavoriteButton(place: place) } }
        .sheet(item: $addingPlace) { place in NavigationStack { AddPlaceEditor(place: place, day: store.selectedDay) } }
        .fullScreenCover(item: $gallery) { ImageGallery(selection: $0) }
    }
    private func detail(_ title: String, text: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) { Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(TripStyle.green); Text(text).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled) }
    }
}
struct HotelDetail: View {
    @Environment(TripStore.self) private var store
    var hotel: Hotel
    @State private var stay: Stay?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LocalPhoto(path: hotel.photo.path, height: 280, pixelSize: 1400)
                VStack(alignment: .leading, spacing: 22) {
                    Eyebrow(text: hotel.en.uppercased())
                    SectionTitle(title: hotel.name, subtitle: hotel.reason)
                    Button((store.plan.hotelFavorites ?? []).contains(hotel.id) ? "已收藏酒店" : "收藏这家酒店", systemImage: "heart") {
                        _ = store.edit { p in var ids = p.hotelFavorites ?? []; if ids.contains(hotel.id) { ids.removeAll { $0 == hotel.id } } else { ids.append(hotel.id) }; p.hotelFavorites = ids }
                    }.buttonStyle(.glass)
                    Button("登记我们的住宿", systemImage: "bed.double") { var value = Stay(); value.name = hotel.name; value.nameEnglish = hotel.en; value.address = hotel.address; stay = value }.buttonStyle(.glassProminent)
                    if !hotel.notice.isEmpty { Label(hotel.notice, systemImage: "info.circle").font(.subheadline).foregroundStyle(TripStyle.coral) }
                    Text(hotel.address).font(.subheadline).textSelection(.enabled)
                    Map(initialPosition: .region(.init(center: .init(latitude: hotel.coords[0], longitude: hotel.coords[1]), span: .init(latitudeDelta: 0.018, longitudeDelta: 0.018)))) { Marker(hotel.name, coordinate: .init(latitude: hotel.coords[0], longitude: hotel.coords[1])) }.frame(height: 200).clipShape(.rect(cornerRadius: 20))
                    DestinationMapButton(title: "在 Apple 地图打开", query: hotel.address, name: hotel.name, coordinates: hotel.coords)
                    SectionTitle(title: "房型与报价", subtitle: "\(store.content.trip.dateRangeLabel) · \(store.content.trip.partySize) 人 · \(store.content.trip.nightCount)晚含税快照")
                    ForEach(Array(hotel.rooms.enumerated()), id: \.offset) { _, room in
                        PaperCard { VStack(alignment: .leading, spacing: 10) {
                            Text(room.name).font(.headline)
                            Text(room.bed).font(.subheadline)
                            if let total = room.quote.totalHome { Text("\(store.content.trip.currency.homeSymbol)\(total, specifier: "%.0f") / \(store.content.trip.nightCount)晚").font(.title3.weight(.medium)).foregroundStyle(TripStyle.green) }
                            Text([room.quote.breakfast, room.quote.cancel, room.quote.confirmation, room.quote.extraFees].compactMap { $0 }.joined(separator: "\n")).font(.footnote).foregroundStyle(.secondary)
                        } }
                    }
                    SectionTitle(title: "住下之前")
                    ForEach(hotel.policies + hotel.transport, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                    Text("核对日期：\(hotel.checkedAt)。报价不是当前库存，收藏不代表已预订。").font(.caption).foregroundStyle(.secondary)
                    if let url = URL(string: hotel.source) { Link("查看预订来源 ↗", destination: url) }
                }.padding(22)
            }
        }.background(TripStyle.paper).navigationTitle(hotel.name).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $stay) { value in NavigationStack { StayEditor(stay: value) } }
    }
}
