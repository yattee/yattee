import Defaults
import Foundation

final class RecentsModel: ObservableObject {
    static var shared = RecentsModel()

    @Default(.recentlyOpened) var items
    @Default(.saveRecents) var saveRecents

    func clear() {
        items = []
    }

    func clearQueries() {
        items.removeAll { $0.type == .query }
    }

    func add(_ item: RecentItem) {
        if !saveRecents {
            clear()

            if item.type == .query {
                return
            }
        }

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        }

        items.append(item)
    }

    func close(_ item: RecentItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        }
    }

    func addQuery(_ query: String) {
        if !query.isEmpty {
            if NavigationModel.shared.tabSelection != .search {
                NavigationModel.shared.tabSelection = .search
            }
            add(.init(from: query))
        }
    }

    var presentedChannel: Channel? {
        if let recent = items.last(where: { $0.type == .channel }) {
            return recent.channel
        }

        return nil
    }

    var presentedPlaylist: ChannelPlaylist? {
        if let recent = items.last(where: { $0.type == .playlist }) {
            return recent.playlist
        }

        return nil
    }

    var presentedItem: RecentItem? {
        guard let recent = items.last else { return nil }

        return recent
    }

    static func symbolSystemImage(_ name: String) -> String {
        let firstLetter = name.first?.lowercased()
        let regex = #"^[a-z0-9]$"#

        let symbolName = firstLetter?.range(of: regex, options: .regularExpression) != nil ? firstLetter! : "questionmark"

        return "\(symbolName).circle"
    }
}

struct RecentItem: Defaults.Serializable, Identifiable {
    static var bridge = RecentItemBridge()

    enum ItemType: String {
        case channel, playlist, query
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

        return Channel(app: .invidious, id: id, name: title)
    }

    var playlist: ChannelPlaylist? {
        guard type == .playlist else {
            return nil
        }

        return ChannelPlaylist(id: id, title: title)
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

    init(from query: String) {
        type = .query
        id = query
        title = query
    }

    init(from playlist: ChannelPlaylist) {
        type = .playlist
        id = playlist.id
        title = playlist.title
    }
}

struct RecentItemBridge: Defaults.Bridge {
    typealias Value = RecentItem
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else {
            return nil
        }

        return [
            "type": value.type.rawValue,
            "identifier": value.id,
            "title": value.title
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object,
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
