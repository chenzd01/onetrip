import SwiftUI

struct DiningFilters {
    var category = "全部"
    var award = "全部"
    var zone = "全部"
    var budget = "全部"

    var isActive: Bool { category != "全部" || award != "全部" || zone != "全部" || budget != "全部" }
}

private struct DiningFactBlock: View {
    var title: String
    var text: String
    var icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(TripStyle.green)
            Text(text).font(.subheadline).foregroundStyle(.secondary).lineSpacing(5).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiningFilterMenu: View {
    var title: String
    @Binding var selection: String
    var values: [String]
    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(values, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection == "全部" ? title : selection)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .padding(.horizontal, 13).frame(minHeight: 44)
            .background(selection == "全部" ? TripStyle.card : TripStyle.green.opacity(0.1), in: .capsule)
            .foregroundStyle(TripStyle.green)
        }.accessibilityLabel(title + "，" + selection)
    }
}

struct DiningListView: View {
    @Environment(TripStore.self) private var store
    var search: String = ""
    @Binding var filters: DiningFilters
    var day: Int? = nil
    private var venues: [DiningVenue] {
        (store.content.dining?.restaurants ?? []).enumerated().sorted {
            let left = $0.element.depth == "directory" ? 1 : 0
            let right = $1.element.depth == "directory" ? 1 : 0
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
    private var results: [DiningVenue] {
        venues.filter { venue in
            let text = ([venue.name, venue.en, venue.zone] + venue.cuisines).joined(separator: " ")
            let categoryMatches = filters.category == "全部" || (filters.category == "正式餐厅" ? venue.isRestaurant : !venue.isRestaurant)
            let awardMatches = filters.award == "全部" || awardFilter(venue) == filters.award
            let minimum = venue.menus.compactMap(\.totalPerPerson).min()
            let budgetMatches = filters.budget == "全部" || minimum.map { value in
                switch budgetOptions.firstIndex(of: filters.budget) {
                case 1: return value <= 50
                case 2: return value > 50 && value <= 150
                case 3: return value > 150 && value <= 300
                default: return value > 300
                }
            } == true
            return (search.isEmpty || text.localizedStandardContains(search)) && categoryMatches && awardMatches && budgetMatches && (filters.zone == "全部" || venue.zone == filters.zone)
        }
    }
    private var budgetOptions: [String] {
        let symbol = store.content.trip.currency.localSymbol
        return ["全部", "\(symbol)50 以内", "\(symbol)50–150", "\(symbol)150–300", "\(symbol)300 以上"]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NavigationLink { DiningSuggestionsView(day: day ?? store.selectedDay) } label: {
                HStack(spacing: 12) {
                    Label("\(store.content.trip.dayCount) 天怎么吃", systemImage: "calendar")
                    Spacer(minLength: 4)
                    Text("查看用餐建议").font(.caption)
                    Image(systemName: "chevron.right").font(.caption)
                }.font(.subheadline).foregroundStyle(TripStyle.green)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(TripStyle.card, in: .rect(cornerRadius: 14))
            }.buttonStyle(.plain)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    DiningFilterMenu(title: "类型", selection: $filters.category, values: ["全部", "小吃与平价餐饮", "正式餐厅"])
                    DiningFilterMenu(title: "米其林", selection: $filters.award, values: ["全部", "一星", "二星", "三星", "必比登", "指南入选"])
                    DiningFilterMenu(title: "区域", selection: $filters.zone, values: ["全部"] + Set(venues.map(\.zone)).sorted())
                    DiningFilterMenu(title: "人均预算", selection: $filters.budget, values: budgetOptions)
                }
            }.scrollIndicators(.hidden)
            HStack {
                Text("\(results.count) 处餐饮").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if filters.isActive { Button("清除筛选") { filters = DiningFilters() }.font(.caption).frame(minHeight: 44) }
            }
            if filters.budget != "全部" {
                Text("按已核实可换算的含税人均起价筛选；价格待核实的餐厅未列入。午晚餐及酒水可能不同。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if results.isEmpty {
                ContentUnavailableView("没有符合条件的餐饮", systemImage: "fork.knife", description: Text("试试其他区域、预算，或清除筛选。"))
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(results) { venue in
                        if let place = store.place(venue.id) {
                            NavigationLink { DiningDetail(place: place, day: day) } label: { DiningVenueCard(venue: venue) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if let directory = store.content.dining?.directory {
                VStack(alignment: .leading, spacing: 8) {
                    Text("米其林 \(String(directory.edition)) · 内容核对于 \(store.content.dining?.checkedAt ?? "待核实")")
                    Text(directory.notes)
                    if let url = URL(string: directory.sourceURL) { Link("查看米其林官方名录 ↗", destination: url) }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func awardFilter(_ venue: DiningVenue) -> String {
        switch venue.award.kind {
        case "stars": return [1: "一星", 2: "二星", 3: "三星"][venue.award.stars ?? 0] ?? ""
        case "bibGourmand": return "必比登"
        case "selected": return "指南入选"
        default: return ""
        }
    }
}

private struct DiningVenueCard: View {
    @Environment(TripStore.self) private var store
    var venue: DiningVenue
    var meal: String? = nil
    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                if !venue.award.label.isEmpty { Text(venue.award.label).font(.caption.weight(.semibold)).foregroundStyle(TripStyle.coral) }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(venue.name).font(.title3.weight(.semibold)).foregroundStyle(TripStyle.green)
                        if venue.en != venue.name { Text(venue.en).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 5)
                }
                Text(([venue.zone] + venue.cuisines).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                if venue.depth != "directory" { Text(venue.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                if venue.depth == "directory" { Text("名录收录 · 菜单与预约详情待核实").font(.caption).foregroundStyle(.secondary) }
                if let menu = venue.referenceMenu(for: meal) {
                    DiningPriceSummary(menu: menu, compact: true)
                } else {
                    Label((meal.map { MealPlan.label($0) } ?? "人均") + "价格待核实", systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
                }
                if !(venue.booking.observations ?? []).isEmpty {
                    Text("含餐位查询记录 · 预订前请实时复查").font(.caption).foregroundStyle(.secondary)
                } else if venue.isRestaurant && ["notChecked", "unknown"].contains(venue.booking.availability) {
                    Text("旅行日期的空位尚未核实").font(.caption).foregroundStyle(.secondary)
                }
                Label(venue.isRestaurant ? "查看预约规则与官方入口" : "查看推荐吃法与地点", systemImage: venue.isRestaurant ? "calendar" : "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(TripStyle.green).padding(.top, 2)
            }
        }
    }
}

private struct DiningPriceSummary: View {
    @Environment(TripStore.self) private var store
    var menu: DiningMenu
    var compact = false
    private func amount(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func range(_ low: Double, factor: Double = 1) -> String {
        let high = menu.priceMax.flatMap { max in menu.price.map { base in base > 0 ? low * max / base : low } }
        if let high, high > low { return amount(low * factor) + "–" + amount(high * factor) }
        return amount(low * factor)
    }
    var body: some View {
        let c = store.content.trip.currency, party = Double(store.content.trip.partySize), rate = c.homePerLocal
        VStack(alignment: .leading, spacing: 6) {
            if let total = menu.totalPerPerson {
                Text("\(c.localSymbol)\(range(total)) / 人\(menu.basis == "estimate" ? " · 估算" : " · 含税费")")
                    .font(compact ? .subheadline.weight(.semibold) : .title3.weight(.semibold)).foregroundStyle(TripStyle.green)
                Text("约 \(c.homeSymbol)\(range(total, factor: rate)) / 人")
                    .font(.caption).foregroundStyle(.secondary)
                if !compact {
                    Text("\(store.content.trip.partySize) 人约 \(c.localSymbol)\(range(total, factor: party)) · \(c.homeSymbol)\(range(total, factor: party * rate))")
                        .font(.subheadline).foregroundStyle(TripStyle.green)
                }
            } else if let price = menu.price {
                if menu.basis == "perPerson" || menu.basis == "estimate" {
                    Text("\(c.localSymbol)\(range(price)) / 人 · " + (menu.tax == "++" ? "未含服务费与税费" : "税费是否已含待核实"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(TripStyle.green)
                    Text("约 \(c.homeSymbol)\(range(price, factor: rate)) / 人 · 仅餐价")
                        .font(.caption).foregroundStyle(.secondary)
                    if !compact {
                        Text("\(store.content.trip.partySize) 人餐价 \(c.localSymbol)\(range(price, factor: party)) · 约 \(c.homeSymbol)\(range(price, factor: party * rate))，" + (menu.tax == "++" ? "税费另计，费率待核实" : "税费是否已含待核实"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("\(c.localSymbol)\(amount(price))\(menu.priceMax.map { "–" + amount($0) } ?? "") · 公布价")
                        .font(.headline).foregroundStyle(TripStyle.green)
                    Text(["perDish": "按每道菜计价，请按人数与点菜量判断。", "perSet": "按每份套餐计价，人数以菜单说明为准。", "perTable": "按每桌计价，人数以菜单说明为准。", "marketPrice": "按时价计费，请向餐厅确认。 "][menu.basis] ?? "价格单位待核实，暂不换算成人均。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("价格待核实").font(.headline).foregroundStyle(.secondary)
            }
            if compact { Text(menu.name).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct DiningDetail: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    var place: Place
    var day: Int? = nil
    var meal = "lunch"
    @State private var addingPlace: Place?
    private var venue: DiningVenue? { store.content.dining?.venue(place.id) }
    var body: some View {
        ScrollView {
            if let venue {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !venue.award.label.isEmpty { Text(venue.award.label).font(.subheadline.weight(.semibold)).foregroundStyle(TripStyle.coral) }
                        Text(venue.name).font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                        if venue.en != venue.name { Text(venue.en).font(.subheadline).foregroundStyle(.secondary) }
                        Text(([venue.zone] + venue.cuisines).joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        Text(venue.description).font(.title3).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    priceSection(venue)
                    bookingSection(venue)
                    DiningFactBlock(title: "在哪里吃", text: venue.address.isEmpty ? "详细地址待核实，可用英文店名在地图中查找。" : venue.address, icon: "mappin.and.ellipse")
                    DiningFactBlock(title: "什么时候去", text: venue.hours, icon: "clock")
                    if !venue.tips.isEmpty {
                        DiningFactBlock(title: "吃之前知道这些", text: venue.tips.joined(separator: "\n\n"), icon: "sparkles")
                    }
                    relatedGuides(venue)
                    DiningSourcesView(sources: venue.sources)
                }.padding(22)
            } else {
                ContentUnavailableView("餐饮信息暂不可用", systemImage: "fork.knife", description: Text("已有行程仍然保留，请返回后重试。"))
            }
        }.background(TripStyle.paper).navigationTitle(place.name).navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let venue {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))) {
                    DestinationMapButton(query: venue.address.isEmpty ? venue.en : venue.address, name: venue.en, coordinates: venue.coordinates.map { [$0.latitude, $0.longitude] }).buttonStyle(.glass)
                    Button { addingPlace = place } label: { Label("加入行程", systemImage: "plus").frame(maxWidth: .infinity).padding(6) }.buttonStyle(.glassProminent)
                }.padding(.horizontal, 22).padding(.vertical, 10).background(.regularMaterial)
            }
        }
        .sheet(item: $addingPlace) { place in NavigationStack { MealEditor(place: place, day: day ?? store.selectedDay, kind: meal) } }
    }
    private func priceSection(_ venue: DiningVenue) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "这一餐大概多少钱", subtitle: "参考餐费不会自动修改旅行预算")
            if venue.menus.isEmpty {
                PaperCard { Text("尚未取得可靠菜单报价。请从官方入口确认当日菜单、税费及酒水。") .font(.subheadline).foregroundStyle(.secondary) }
            }
            ForEach(Array(venue.menus.enumerated()), id: \.offset) { _, menu in
                PaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(menu.name).font(.headline)
                        DiningPriceSummary(menu: menu)
                        if !menu.includes.isEmpty { Text(menu.includes).font(.subheadline).foregroundStyle(.secondary) }
                        Text(priceBasis(menu)).font(.caption).foregroundStyle(.secondary)
                        Text("核对日期：" + menu.checkedAt).font(.caption).foregroundStyle(.secondary)
                        if let url = URL(string: menu.sourceURL), !menu.sourceURL.isEmpty { Link("查看菜单来源 ↗", destination: url).font(.caption) }
                    }
                }
            }
            Text("\(store.content.trip.currency.home) 按 1 \(store.content.trip.currency.local) ≈ \(store.content.trip.currency.homePerLocal, specifier: "%.4f") \(store.content.trip.currency.home) 换算（\(store.content.trip.currency.rateDate)），实际以餐厅账单及支付汇率为准。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func priceBasis(_ menu: DiningMenu) -> String {
        var labels: [String] = []
        if let price = menu.price { labels.append("原价 " + store.content.trip.currency.localSymbol + price.formatted(.number.precision(.fractionLength(0...2)))) }
        switch menu.basis {
        case "perPerson": labels.append("每人")
        case "estimate": labels.append("参考估算")
        case "perDish": labels.append("每道菜")
        case "perTable": labels.append("每桌")
        default: labels.append("计价单位以菜单为准")
        }
        if menu.tax == "nett" { labels.append("净价") }
        else if let service = menu.serviceChargePercent, let tax = menu.taxPercent {
            labels.append("服务费 \(service.formatted())%，另计税费 \(tax.formatted())%")
        } else { labels.append("税费口径待核实") }
        return labels.joined(separator: " · ")
    }
    private func bookingSection(_ venue: DiningVenue) -> some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: venue.isRestaurant ? "预约这顿饭" : "到店怎么吃")
                Text(venue.booking.policy).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                if let release = venue.booking.releaseRule, !release.isEmpty { DiningFactBlock(title: "放位规则", text: release, icon: "calendar") }
                if let cancellation = venue.booking.cancellation, !cancellation.isEmpty { DiningFactBlock(title: "取消与订金", text: cancellation, icon: "creditcard") }
                if venue.isRestaurant {
                    Text((venue.booking.observations ?? []).isEmpty ? availabilityLabel(venue.booking.availability) : "以下是查询时的记录，当前空位请以官方预约页面为准。")
                        .font(.subheadline).foregroundStyle(TripStyle.green)
                }
                ForEach(venue.booking.observations ?? []) { observation in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(observation.date) · \(MealPlan.label(observation.meal)) · \(observation.partySize) 人").font(.subheadline.weight(.medium))
                        Text(availabilityLabel(observation.status)).font(.caption.weight(.medium)).foregroundStyle(TripStyle.green)
                        Text(observation.detail).font(.subheadline).foregroundStyle(.secondary)
                        Text("查询于 " + observation.checkedAt).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let url = URL(string: venue.booking.url), !venue.booking.url.isEmpty {
                    Link(destination: url) { Label(bookingLinkLabel(venue), systemImage: "safari").frame(maxWidth: .infinity).padding(6) }.buttonStyle(.glass)
                }
                Text("核对于 \(venue.booking.checkedAt)。" + (venue.isRestaurant ? "加入行程不会替你预订；预约成功后可在用餐安排中登记。" : "摊位营业时间和排队情况以当天现场为准。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func availabilityLabel(_ status: String) -> String {
        switch status {
        case "notChecked", "unknown": return "尚未核实旅行日期的空位，请打开预约入口选择日期与人数。"
        case "notRequired", "walkIn": return "以现场排队为主；排队时间随时段变化。"
        case "available": return "查询时曾有空位，当前情况请以预约页面为准。"
        case "full", "soldOut": return "查询时未见空位，可留意候补或其他时段。"
        case "waitlist": return "查询时仅提供候补；加入候补不代表预约成功。"
        case "notReleased": return "查询时尚未开放该日期，请按放位规则再查。"
        case "closed": return "查询日期不营业。"
        case "blocked": return "未能完成线上核查，请直接打开官方入口。"
        default: return "空位情况未核实，请查看官方预约页面。"
        }
    }
    private func bookingLinkLabel(_ venue: DiningVenue) -> String {
        if !venue.isRestaurant { return "查看地点与到店信息 ↗" }
        if URL(string: venue.booking.url)?.host?.contains("guide.michelin.com") == true { return "从米其林查看餐厅与预约入口 ↗" }
        return venue.isRestaurant ? "打开官方预约入口 ↗" : "查看官方到店信息 ↗"
    }
    @ViewBuilder private func relatedGuides(_ venue: DiningVenue) -> some View {
        let guides = (store.content.dining?.guides ?? []).filter { $0.restaurantIDs.contains(venue.id) }
        let posts = store.content.posts.filter { ($0.guidePlaces ?? []).contains(venue.id) }
        if !guides.isEmpty || !posts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "出发前，看看这些")
                ForEach(guides) { guide in NavigationLink { DiningGuideDetail(guide: guide) } label: { DiningGuideCard(guide: guide) }.buttonStyle(.plain) }
                ForEach(posts) { post in
                    NavigationLink { PostDetail(post: post) } label: {
                        PaperCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(post.platformName + " · " + post.author, systemImage: "book.pages").font(.caption).foregroundStyle(TripStyle.coral)
                                Text(post.title).font(.headline).foregroundStyle(.primary)
                                Text("实地分享 · 原图已离线").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct DiningSuggestionsView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDay: Int
    init(day: Int) { _selectedDay = State(initialValue: day) }
    private var dayPicker: some View {
        Picker("用餐建议日期", selection: $selectedDay) {
            ForEach(Array(store.plan.days.enumerated()), id: \.element.id) { index, day in Text(String(day.date.suffix(5))).tag(index) }
        }
    }
    private var recommendations: [DiningRecommendation] {
        (store.content.dining?.recommendations ?? []).filter { $0.day == selectedDay }
    }
    private var sameZoneVenues: [DiningVenue] {
        guard store.plan.days.indices.contains(selectedDay) else { return [] }
        let day = store.plan.days[selectedDay]
        let zones = Set(day.items.compactMap { item in
            store.place(item.place).flatMap { place in
                place.isDining || ["自定义", ""].contains(place.zone) ? nil : place.zone
            }
        })
        let suggested = Set(recommendations.flatMap(\.restaurantIDs))
        return (store.content.dining?.restaurants ?? []).filter {
            zones.contains($0.zone) && !suggested.contains($0.id) && !diningIsClosed($0, on: day.date)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(title: "为这一天选一顿好饭", subtitle: "结合当天路线挑选候选，选好后再加入。")
                if typeSize.isAccessibilitySize { dayPicker.pickerStyle(.menu) }
                else { dayPicker.pickerStyle(.segmented) }
                if store.plan.days.indices.contains(selectedDay) {
                    let tripDay = store.plan.days[selectedDay]
                    let names = tripDay.items.compactMap { item in store.place(item.place).flatMap { $0.isDining ? nil : $0.name } }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 9) {
                            Label("这一天的路线", systemImage: "map").font(.subheadline.weight(.semibold)).foregroundStyle(TripStyle.green)
                            Text(names.isEmpty ? "还没有安排游览地点" : names.joined(separator: " → "))
                                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                            Text("以下是行程参考建议；更改路线后，请结合实际位置与营业时间选择。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink { DiningCatalogScreen(day: selectedDay) } label: {
                    Label("从全部餐饮中挑选", systemImage: "magnifyingglass").frame(minHeight: 44)
                }.buttonStyle(.glass)
                if !sameZoneVenues.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "与当天行程同区域", subtitle: "按你当前的游览安排匹配；已排除公布的店休日，具体路程请查看地图。")
                        ForEach(sameZoneVenues) { venue in
                            if let place = store.place(venue.id) {
                                DiningSuggestedVenue(venue: venue, place: place, day: selectedDay, meal: "lunch", genericMeal: true)
                            }
                        }
                    }
                }
                if recommendations.isEmpty && sameZoneVenues.isEmpty {
                    ContentUnavailableView("暂无适合这一天的区域推荐", systemImage: "fork.knife", description: Text("可以从全部餐饮中选择喜欢的餐厅，再安排时间。"))
                }
                ForEach(recommendations) { recommendation in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(MealPlan.label(recommendation.meal)).font(.caption.weight(.semibold)).foregroundStyle(TripStyle.coral)
                        SectionTitle(title: recommendation.title, subtitle: recommendation.reason)
                        ForEach(recommendation.restaurantIDs, id: \.self) { id in
                            if let venue = store.content.dining?.venue(id), let place = store.place(id) {
                                DiningSuggestedVenue(venue: venue, place: place, day: selectedDay, meal: recommendation.meal)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }.padding(22)
        }.background(TripStyle.paper).navigationTitle("用餐建议").navigationBarTitleDisplayMode(.inline)
    }
}

private struct DiningSuggestedVenue: View {
    @Environment(TripStore.self) private var store
    var venue: DiningVenue
    var place: Place
    var day: Int
    var meal: String
    var genericMeal = false
    @State private var addingPlace: Place?
    private var added: Bool { store.plan.days.indices.contains(day) && store.plan.days[day].items.contains { $0.place == place.id && (genericMeal || $0.meal?.kind == meal) } }
    var body: some View {
        VStack(spacing: 0) {
            NavigationLink { DiningDetail(place: place, day: day, meal: meal) } label: { DiningVenueCard(venue: venue, meal: genericMeal ? nil : meal) }.buttonStyle(.plain)
            if store.plan.days.indices.contains(day), diningIsClosed(venue, on: store.plan.days[day].date) {
                Label("这一天是公布的店休日，请确认营业安排后再添加。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(TripStyle.coral).padding(.horizontal, 18).padding(.bottom, 12)
            }
            if added {
                Label(genericMeal ? "已在这一天的安排中" : "已在这一天的\(MealPlan.label(meal))安排中", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(TripStyle.green).padding(.bottom, 18)
            } else {
                Button { addingPlace = place } label: { Label(genericMeal ? "安排这一餐" : "安排为" + MealPlan.label(meal), systemImage: "plus").frame(maxWidth: .infinity).padding(5) }
                    .buttonStyle(.glass).padding(.horizontal, 18).padding(.bottom, 18)
            }
        }.background(TripStyle.card, in: .rect(cornerRadius: 24))
        .sheet(item: $addingPlace) { place in NavigationStack { MealEditor(place: place, day: day, kind: meal) } }
    }
}

struct DiningGuideListView: View {
    @Environment(TripStore.self) private var store
    var search: String = ""
    private var guides: [DiningGuide] {
        (store.content.dining?.guides ?? []).filter { search.isEmpty || ($0.title + $0.summary).localizedStandardContains(search) }
    }
    var body: some View {
        if !guides.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "好好吃饭的功课", subtitle: "实用餐饮指南 · 价格与预约见餐厅最新核实记录")
                ForEach(guides) { guide in
                    NavigationLink { DiningGuideDetail(guide: guide) } label: { DiningGuideCard(guide: guide) }.buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DiningGuideCard: View {
    var guide: DiningGuide
    var body: some View {
        PaperCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "book.closed").font(.title3).foregroundStyle(TripStyle.coral).padding(.top, 3)
                VStack(alignment: .leading, spacing: 7) {
                    Text(guide.title).font(.headline).foregroundStyle(TripStyle.green)
                    Text(guide.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 5)
            }
        }
    }
}

struct DiningGuideDetail: View {
    @Environment(TripStore.self) private var store
    var guide: DiningGuide
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: store.content.trip.destination.nameEn.uppercased() + " · GOOD FOOD, GOOD COMPANY")
                Text(guide.title).font(.system(.largeTitle, design: .serif, weight: .semibold)).foregroundStyle(TripStyle.green)
                Text(guide.summary).font(.title3).foregroundStyle(.secondary).lineSpacing(5)
                ForEach(Array(guide.body.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).font(.body).lineSpacing(7).textSelection(.enabled)
                }
                if !guide.restaurantIDs.isEmpty {
                    SectionTitle(title: "这篇攻略里提到的餐饮")
                    ForEach(guide.restaurantIDs, id: \.self) { id in
                        if let venue = store.content.dining?.venue(id), let place = store.place(id) {
                            NavigationLink { DiningDetail(place: place) } label: { DiningVenueCard(venue: venue) }.buttonStyle(.plain)
                        }
                    }
                }
                DiningSourcesView(sources: guide.sources)
            }.padding(22)
        }.background(TripStyle.paper).navigationTitle("餐饮攻略").navigationBarTitleDisplayMode(.inline)
    }
}

private struct DiningSourcesView: View {
    var sources: [DiningSource]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("资料来源与核实日期").font(.subheadline.weight(.semibold)).foregroundStyle(TripStyle.green)
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                VStack(alignment: .leading, spacing: 4) {
                    if let url = URL(string: source.url) { Link(source.title + " ↗", destination: url).font(.subheadline).frame(minHeight: 44, alignment: .leading) }
                    else { Text(source.title).font(.subheadline) }
                    Text("核对于 " + source.checkedAt).font(.caption).foregroundStyle(.secondary)
                }
            }
            if sources.isEmpty { Text("来源信息待补充，请以餐厅官方说明为准。").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct DiningCatalogScreen: View {
    var day: Int
    @State private var search = ""
    @State private var filters = DiningFilters()
    var body: some View {
        ScrollView { DiningListView(search: search, filters: $filters, day: day).padding(22) }
            .background(TripStyle.paper).navigationTitle("挑选餐饮").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索餐厅、菜系、区域")
    }
}

private func diningIsClosed(_ venue: DiningVenue, on date: String) -> Bool {
    DiningSchedule.isClosed(venue, on: date)
}
