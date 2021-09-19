import Defaults
import Foundation

final class Recents: ObservableObject {
    @Default(.recentlyOpened) var items

    var isEmpty: Bool {
        items.isEmpty
    }

    func clear() {
        items = []
    }

    func clearQueries() {
        items.removeAll { $0.type == .query }
    }

    func open(_ item: RecentItem) {
        if !items.contains(where: { $0.id == item.id }) {
            items.append(item)
        }
    }

    func close(_ item: RecentItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        }
    }

    var presentedChannel: Channel? {
        if let recent = items.last(where: { $0.type == .channel }) {
            return recent.channel
        }

        return nil
    }
}

struct RecentItem: Defaults.Serializable, Identifiable {
    static var bridge = RecentItemBridge()

    enum ItemType: String {
        case channel, query
    }

    var type: ItemType
    var id: String
    var title: String

    var tag: String {
        "recent\(type.rawValue.capitalized)\(id)"
    }

    var query: SearchQuery? {
        guard type == .query else {
            return nil
        }

        return SearchQuery(query: title)
    }

    var channel: Channel? {
        guard type == .channel else {
            return nil
        }

        return Channel(id: id, name: title)
    }

    init(type: ItemType, identifier: String, title: String) {
        self.type = type
        id = identifier
        self.title = title
    }

    init(from channel: Channel) {
        type = .channel
        id = channel.id
        title = channel.name
    }
}

struct RecentItemBridge: Defaults.Bridge {
    typealias Value = RecentItem
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value = value else {
            return nil
        }

        return [
            "type": value.type.rawValue,
            "identifier": value.id,
            "title": value.title
        ]
    }

    func deserialize(_ object: Serializable?) -> RecentItem? {
        guard
            let object = object,
            let type = object["type"],
            let identifier = object["identifier"],
            let title = object["title"]
        else {
            return nil
        }

        return RecentItem(
            type: .init(rawValue: type)!,
            identifier: identifier,
            title: title
        )
    }
}
