import Foundation
import SwiftUI

struct FavoriteButton: View {
    let item: FavoriteItem
    let favorites = FavoritesModel.shared

    @State private var isFavorite = false

    var body: some View {
        Button {
            favorites.toggle(item)
            isFavorite.toggle()
        } label: {
            if isFavorite {
                Label("Remove from Favorites", systemImage: "heart.fill")
            } else {
                Label("Add to Favorites", systemImage: "heart")
            }
        }
        .onAppear {
            isFavorite = favorites.contains(item)
        }
    }
}
