import Defaults
import Foundation

struct FavoritesModel {
    static let shared = Self()

    @Default(.showFavoritesInHome) var showFavoritesInHome
    @Default(.favorites) var all
    @Default(.widgetsSettings) var widgetsSettings

    var isEnabled: Bool {
        showFavoritesInHome
    }

    func contains(_ item: FavoriteItem) -> Bool {
        all.contains { $0 == item }
    }

    func toggle(_ item: FavoriteItem) {
        if contains(item) {
            remove(item)
        } else {
            add(item)
        }
    }

    func add(_ item: FavoriteItem) {
        if contains(item) { return }
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
            FavoriteItem(section: .popular),
            FavoriteItem(section: .history)
        ]

        return allItems.filter { item in !all.contains { $0.section == item.section } }
    }

    func listingStyle(_ item: FavoriteItem) -> WidgetListingStyle {
        widgetSettings(item).listingStyle
    }

    func limit(_ item: FavoriteItem) -> Int {
        min(WidgetSettings.maxLimit(listingStyle(item)), widgetSettings(item).limit)
    }

    func setListingStyle(_ style: WidgetListingStyle, _ item: FavoriteItem) {
        if let index = widgetsSettings.firstIndex(where: { $0.id == item.widgetSettingsKey }) {
            var settings = widgetsSettings[index]
            settings.listingStyle = style
            widgetsSettings[index] = settings
        } else {
            let settings = WidgetSettings(id: item.widgetSettingsKey, listingStyle: style)
            widgetsSettings.append(settings)
        }
    }

    func setLimit(_ limit: Int, _ item: FavoriteItem) {
        if let index = widgetsSettings.firstIndex(where: { $0.id == item.widgetSettingsKey }) {
            var settings = widgetsSettings[index]
            let limit = min(max(1, limit), WidgetSettings.maxLimit(settings.listingStyle))
            settings.limit = limit
            widgetsSettings[index] = settings
        } else {
            var settings = WidgetSettings(id: item.widgetSettingsKey, limit: limit)
            let limit = min(max(1, limit), WidgetSettings.maxLimit(settings.listingStyle))
            settings.limit = limit
            widgetsSettings.append(settings)
        }
    }

    func widgetSettings(_ item: FavoriteItem) -> WidgetSettings {
        widgetsSettings.first { $0.id == item.widgetSettingsKey } ?? WidgetSettings(id: item.widgetSettingsKey)
    }

    func updateWidgetSettings(_ settings: WidgetSettings) {
        if let index = widgetsSettings.firstIndex(where: { $0.id == settings.id }) {
            widgetsSettings[index] = settings
        } else {
            widgetsSettings.append(settings)
        }
    }
}
