import SwiftUI
import MapKit
import OSLog

struct DestinationMapButton: View {
    @Environment(TripStore.self) private var store
    var title: String = "导航"
    var query: String
    var name: String
    var coordinates: [Double]? = nil
    var showsPreview = false
    @State private var choosingDestination = false

    var body: some View {
        Button {
            if let item = DestinationMaps.item(name: name, address: query, coordinates: coordinates) {
                if !DestinationMaps.open(item) { store.error = "暂时无法打开 Apple 地图，请检查是否已安装地图 App。" }
            } else { choosingDestination = true }
        } label: {
            if showsPreview { mapPreview } else { Label(title, systemImage: "location") }
        }
        .sheet(isPresented: $choosingDestination) {
            NavigationStack { DestinationPicker(query: query) }
                .presentationDetents([.medium, .large])
        }
    }

    private var mapPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("在\(TripConfig.current.destination.name)的位置", systemImage: "map").font(.headline).foregroundStyle(TripStyle.green)
            if let item = DestinationMaps.item(name: name, address: query, coordinates: coordinates) {
                Map(initialPosition: .region(DestinationMaps.region), interactionModes: []) {
                    Marker(name, coordinate: item.location.coordinate).tint(TripStyle.coral)
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 200).clipShape(.rect(cornerRadius: 16))
                .allowsHitTesting(false).accessibilityHidden(true)
                Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(query).font(.footnote).foregroundStyle(.secondary)
                Label("在 Apple 地图打开", systemImage: "arrow.up.right").font(.subheadline.weight(.medium)).foregroundStyle(TripStyle.green)
            } else {
                Text(query).font(.subheadline).foregroundStyle(.secondary)
                Text("核对搜索结果后，在 Apple 地图查看位置。").font(.footnote).foregroundStyle(.secondary)
                Label("查找地图位置", systemImage: "magnifyingglass").font(.subheadline.weight(.medium)).foregroundStyle(TripStyle.green)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(TripStyle.card, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct DestinationPicker: View {
    @Environment(\.dismiss) private var dismiss
    var query: String
    @State private var items: [MKMapItem] = []
    @State private var searching = true
    @State private var message: String?
    @State private var retry = 0
    @State private var activeSearch: MKLocalSearch?

    var body: some View {
        List {
            Section {
                Text(query).font(.headline).textSelection(.enabled)
                Text("只查找\(TripConfig.current.destination.name)范围内的地点，核对名称和地址后打开地图。").font(.footnote).foregroundStyle(.secondary)
            }
            if searching { ProgressView("正在查找\(TripConfig.current.destination.name)的地点…") }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    if DestinationMaps.open(item) { dismiss() }
                    else { message = "暂时无法打开 Apple 地图，请检查是否已安装地图 App。" }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(item.name ?? query, systemImage: "mappin.circle.fill").font(.headline)
                        Text(item.address?.fullAddress ?? TripConfig.current.destination.nameEn).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
            }
            if let message {
                Section {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                    Button("重新查找", systemImage: "arrow.clockwise") { retry += 1 }
                    Button("复制地点与所在地", systemImage: "doc.on.doc") { UIPasteboard.general.string = [query, TripConfig.current.destination.addressSuffix].filter { !$0.isEmpty }.joined(separator: ", ") }
                }
            }
        }
        .navigationTitle("确认目的地").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        .onDisappear { activeSearch?.cancel() }
        .task(id: retry) {
            searching = true; message = nil; items = []
            let search = MKLocalSearch(request: DestinationMaps.request(for: query))
            activeSearch = search
            do {
                let response = try await search.start()
                guard !Task.isCancelled else { return }
                items = response.mapItems.filter { DestinationMaps.acceptsSearchResult(coordinate: $0.location.coordinate, regionIdentifier: $0.addressRepresentations?.region?.identifier) }
                if items.isEmpty { message = "没有找到可确认的\(TripConfig.current.destination.name)地点。请核对英文名称或地址后重试。" }
            } catch {
                guard !Task.isCancelled else { return }
                let failure = error as NSError
                Logger(subsystem: AppIdentity.appBundleID, category: "maps").error("Place search failed: \(failure.domain, privacy: .public) \(failure.code)")
                message = "暂时无法查找地点，请联网后重试。地点说明和地址仍可离线阅读。"
            }
            searching = false
        }
    }
}

// Hotel handoff does not depend on an in-app place search succeeding first.
enum StayMaps {
    static func destination(_ stay: Stay, coordinates: [Double]? = nil) -> String {
        if let coordinates, coordinates.count == 2,
           DestinationMaps.contains(.init(latitude: coordinates[0], longitude: coordinates[1])) {
            return "\(coordinates[0]),\(coordinates[1])"
        }
        let name = (stay.nameEnglish ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [name.isEmpty ? stay.name : name, stay.address, TripConfig.current.destination.addressSuffix]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: ", ")
    }
    static func url(_ stay: Stay, google: Bool, coordinates: [Double]? = nil) -> URL {
        var url = URLComponents(string: google ? "https://www.google.com/maps/dir/" : "https://maps.apple.com/")!
        let target = destination(stay, coordinates: coordinates)
        url.queryItems = google ? [.init(name: "api", value: "1"), .init(name: "destination", value: target)] : [.init(name: "daddr", value: target)]
        return url.url!
    }
}

struct StayNavigationButton: View {
    @Environment(TripStore.self) private var store
    @Environment(\.openURL) private var openURL
    var stay: Stay
    @State private var choosingMap = false
    private var coordinates: [Double]? {
        store.content.hotels.hotels.first { !$0.address.isEmpty && $0.address == stay.address }?.coords
    }
    var body: some View {
        Button("导航到酒店", systemImage: "location") { choosingMap = true }
            .confirmationDialog("选择地图导航到酒店", isPresented: $choosingMap, titleVisibility: .visible) {
                Button("Apple 地图") { navigate(google: false) }
                Button("Google Maps") { navigate(google: true) }
                Button("取消", role: .cancel) {}
            } message: { Text([stay.nameEnglish ?? stay.name, stay.address].filter { !$0.isEmpty }.joined(separator: "\n")) }
    }
    private func navigate(google: Bool) {
        openURL(StayMaps.url(stay, google: google, coordinates: coordinates)) { accepted in
            if !accepted { store.error = "暂时无法打开地图，请复制酒店英文名或地址，在地图软件中搜索。" }
        }
    }
}
