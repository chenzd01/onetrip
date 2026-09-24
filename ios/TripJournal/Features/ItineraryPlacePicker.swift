import SwiftUI

struct ItineraryPlacePicker: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Int
    @State private var search = ""
    @State private var selectedPlace: Place?
    private var places: [Place] {
        store.allPlaces.filter { !$0.isDining && (search.isEmpty || ($0.name + " " + $0.en + " " + $0.zone).localizedStandardContains(search)) }
    }
    var body: some View {
        List {
            Section {
                Text("选择地点后设置时间段，也可以先设为时间待定。").font(.subheadline).foregroundStyle(.secondary)
            }
            if places.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Section {
                    ForEach(places) { place in
                        Button {
                            selectedPlace = place
                        } label: {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(place.name).font(.headline).foregroundStyle(.primary)
                                    Text(place.zone).font(.caption).foregroundStyle(.secondary)
                                    if !place.desc.isEmpty { Text(place.desc).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(TripStyle.green)
                            }.padding(.vertical, 8)
                        }.buttonStyle(.plain)
                        .accessibilityLabel("添加地点：" + place.name)
                    }
                }
            }
        }
        .navigationTitle("为 " + store.plan.days[day].date.suffix(5).replacingOccurrences(of: "-", with: ".") + " 添加地点")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索名称或区域")
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(item: $selectedPlace) { place in AddPlaceEditor(place: place, day: day, onAdded: { dismiss() }) }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}
