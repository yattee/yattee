import Foundation
import SwiftUI

struct DropFavorite: DropDelegate {
    let item: FavoriteItem
    @Binding var favorites: [FavoriteItem]
    @Binding var current: FavoriteItem?

    func dropEntered(info _: DropInfo) {
        guard item != current else {
            return
        }

        guard let current else {
            return
        }

        let from = favorites.firstIndex(of: current)
        let to = favorites.firstIndex(of: item)

        guard let from, let to else {
            return
        }

        guard favorites[to].id != current.id else {
            return
        }

        favorites.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
    }

    func dropUpdated(info _: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info _: DropInfo) -> Bool {
        current = nil
        return true
    }
}
