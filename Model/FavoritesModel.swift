import Defaults
import Foundation

struct FavoritesModel {
    static let shared = FavoritesModel()

    @Default(.favorites) var all
    @Default(.visibleSections) var visibleSections

    var isEnabled: Bool {
        visibleSections.contains(.favorites)
    }

    func contains(_ item: FavoriteItem) -> Bool {
        all.contains { $0 == item }
    }

    func toggle(_ item: FavoriteItem) {
        contains(item) ? remove(item) : add(item)
    }

    func add(_ item: FavoriteItem) {
        all.append(item)
    }

    func remove(_ item: FavoriteItem) {
        if let index = all.firstIndex(where: { $0 == item }) {
            all.remove(at: index)
        }
    }

    func canMoveUp(_ item: FavoriteItem) -> Bool {
        if let index = all.firstIndex(where: { $0 == item }) {
            return index > all.startIndex
        }

        return false
    }

    func canMoveDown(_ item: FavoriteItem) -> Bool {
        if let index = all.firstIndex(where: { $0 == item }) {
            return index < all.endIndex - 1
        }

        return false
    }

    func moveUp(_ item: FavoriteItem) {
        guard canMoveUp(item) else {
            return
        }

        if let from = all.firstIndex(where: { $0 == item }) {
            all.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: from - 1
            )
        }
    }

    func moveDown(_ item: FavoriteItem) {
        guard canMoveDown(item) else {
            return
        }

        if let from = all.firstIndex(where: { $0 == item }) {
            all.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: from + 2
            )
        }
    }

    func addableItems() -> [FavoriteItem] {
        let allItems = [
            FavoriteItem(section: .subscriptions),
            FavoriteItem(section: .popular)
        ]

        return allItems.filter { item in !all.contains { $0.section == item.section } }
    }
}
