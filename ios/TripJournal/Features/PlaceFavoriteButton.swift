import SwiftUI

struct PlaceFavoriteButton: View {
    var place: Place
    private var favorites: PlaceFavorites { .shared }

    var body: some View {
        Button {
            favorites.toggle(place.id)
        } label: {
            Image(systemName: favorites.contains(place.id) ? "heart.fill" : "heart")
                .font(.body.weight(.semibold))
                .foregroundStyle(favorites.contains(place.id) ? TripStyle.coral : TripStyle.green)
                .frame(minWidth: 44, minHeight: 44)
                .background(.regularMaterial, in: .circle)
        }.buttonStyle(.plain)
        .accessibilityLabel((favorites.contains(place.id) ? "取消收藏地点：" : "收藏地点：") + place.name)
        .accessibilityValue(favorites.contains(place.id) ? "已收藏在本机" : "未收藏")
        .sensoryFeedback(.selection, trigger: favorites.contains(place.id))
    }
}
