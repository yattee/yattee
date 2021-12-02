import Defaults
import Foundation
import SwiftUI

struct FavoriteButton: View {
    let item: FavoriteItem!
    let favorites = FavoritesModel.shared

    @State private var isFavorite = false

    var body: some View {
        Group {
            if favorites.isEnabled {
                Button {
                    guard !item.isNil else {
                        return
                    }

                    favorites.toggle(item)
                    isFavorite.toggle()
                } label: {
                    if isFavorite {
                        Label("Remove from Favorites", systemImage: "heart.fill")
                    } else {
                        Label("Add to Favorites", systemImage: "heart")
                    }
                }
                .disabled(item.isNil)
                .onAppear {
                    isFavorite = item.isNil ? false : favorites.contains(item)
                }
            } else {
                EmptyView()
            }
        }
    }
}
