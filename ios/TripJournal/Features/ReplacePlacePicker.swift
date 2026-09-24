import SwiftUI

struct ReplacePlacePicker: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: Stop
    @State private var search = ""
    @State private var kind = "全部"
    @State private var favoritesOnly = false
    @State private var selectedPlace: Place?
    @State private var creatingPlace = false
    @State private var isEditing = false
    @State private var replacementError: String?
    private var places: [Place] {
        store.allPlaces.filter {
            !$0.isDining && (kind == "全部" || $0.kind == kind) && (!favoritesOnly || PlaceFavorites.shared.contains($0.id)) &&
            (search.isEmpty || ($0.name + " " + $0.en + " " + $0.zone).localizedStandardContains(search))
        }
    }
    var body: some View {
        List {
            Section {
                Text(store.place(item.place)?.name ?? "原地点").font(.headline)
                Text(item.scheduleLabel(fallbackHours: store.place(item.place)?.hours ?? 0)).font(.subheadline.monospacedDigit())
                Text("保留日期、已设时间段、备注和顺序，只更换这条安排的地点。").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("正在更换") }
            Section {
                Toggle("只看本机收藏的地点", isOn: $favoritesOnly)
                Picker("分类", selection: $kind) {
                    Text("全部").tag("全部")
                    ForEach(Array(Set(store.allPlaces.filter { !$0.isDining }.map(\.kind))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                Button("新建自定义地点", systemImage: "plus") { creatingPlace = true }
            }
            Section {
                if places.isEmpty {
                    ContentUnavailableView(favoritesOnly ? "暂无符合条件的收藏地点" : "没有找到地点", systemImage: "mappin.slash", description: Text("试试其他关键词或分类，也可以新建自定义地点。"))
                }
                ForEach(places) { place in
                    Button { selectedPlace = place } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(place.name).font(.headline).foregroundStyle(.primary)
                                Text(place.zone + " · " + place.kind).font(.caption).foregroundStyle(.secondary)
                                if place.id == item.place { Text("当前地点").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if PlaceFavorites.shared.contains(place.id) { Image(systemName: "heart.fill").foregroundStyle(TripStyle.coral) }
                            Image(systemName: selectedPlace?.id == place.id ? "checkmark.circle.fill" : "circle").foregroundStyle(TripStyle.green)
                        }.padding(.vertical, 7).contentShape(.rect)
                    }.buttonStyle(.plain)
                    .accessibilityAddTraits(selectedPlace?.id == place.id ? .isSelected : [])
                }
            }
        }
        .navigationTitle("更换地点").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索地点、英文名称或区域")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("确认更换") {
                    guard let selectedPlace else { return }
                    if store.replacePlace(for: item, with: selectedPlace) { dismiss() }
                    else { replacementError = store.error; store.error = nil }
                }.disabled(selectedPlace == nil || selectedPlace?.id == item.place)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selectedPlace {
                VStack(alignment: .leading, spacing: 4) {
                    Text("将更换为").font(.caption).foregroundStyle(.secondary)
                    Text(selectedPlace.name).font(.headline).foregroundStyle(TripStyle.green)
                    if let replacementError { Label(replacementError, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(TripStyle.coral) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(.regularMaterial)
            }
        }
        .navigationDestination(isPresented: $creatingPlace) {
            CustomPlaceEditor(replacing: item, onReplaced: { dismiss() })
        }
        .onAppear { if !isEditing { store.editingForms += 1; isEditing = true } }
        .onDisappear { if isEditing { store.editingForms -= 1; isEditing = false } }
    }
}
