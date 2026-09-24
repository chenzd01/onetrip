import SwiftUI

struct HotelCompareView: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    var body: some View {
        List {
            Section {
                Text("最多选三家，比较\(store.content.trip.nightCount)晚含税报价、床型与取消条件。价格是已核对快照，预订时以结算页为准。").font(.subheadline).foregroundStyle(.secondary)
                ForEach(store.content.hotels.hotels) { hotel in
                    Toggle(hotel.name, isOn: Binding(get: { selected.contains(hotel.id) }, set: { enabled in if enabled { selected.insert(hotel.id) } else { selected.remove(hotel.id) } }))
                        .disabled(selected.count == 3 && !selected.contains(hotel.id))
                }
            } header: { Text("选择酒店 · \(selected.count)/3") }
            ForEach(store.content.hotels.hotels.filter { selected.contains($0.id) }) { hotel in
                Section(hotel.name) {
                    LabeledContent("区域",value:hotel.region)
                    ForEach(Array(hotel.rooms.enumerated()),id:\.offset) { _,room in
                        VStack(alignment:.leading,spacing:8) {
                            Text(room.name).font(.headline)
                            Text(room.bed).font(.subheadline)
                            if let total = room.quote.totalHome { Text("\(total,format:.currency(code:store.content.trip.currency.home).precision(.fractionLength(0))) / \(store.content.trip.nightCount)晚") }
                            Text([room.quote.breakfast,room.quote.cancel,room.quote.extraFees].compactMap { $0 }.joined(separator:"\n")).font(.footnote).foregroundStyle(.secondary)
                        }.padding(.vertical,6)
                    }
                    Text(hotel.notice).font(.footnote).foregroundStyle(TripStyle.coral)
                    NavigationLink("查看完整资料") { HotelDetail(hotel:hotel) }
                }
            }
        }.navigationTitle("住哪里，慢慢选").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement:.confirmationAction) { Button("完成") { dismiss() } } }
        .onAppear { if selected.isEmpty { selected = Set((store.plan.hotelFavorites ?? []).prefix(3)) } }
    }
}
