import Defaults
import Foundation
import SwiftUI

struct FavoriteButton: View {
    let item: FavoriteItem!
    let favorites = FavoritesModel.shared
    let labelPadding: Bool

    init(item: FavoriteItem?, labelPadding: Bool = false) {
        self.item = item
        self.labelPadding = labelPadding
    }

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
                    Group {
                        if isFavorite {
                            Label("Remove from Favorites", systemImage: "heart.fill")
                        } else {
                            Label("Add to Favorites", systemImage: "heart")
                        }
                    }
                    #if os(iOS)
                    .padding(labelPadding ? 10 : 0)
                    .contentShape(Rectangle())
                    #endif
                }
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
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
