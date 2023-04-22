import Cache
import Foundation
import Logging
import SwiftyJSON

struct BookmarksCacheModel {
    static var shared = Self()
    let logger = Logger(label: "stream.yattee.cache")

    static let bookmarksGroup = "group.stream.yattee.app.bookmarks"
    let defaults = UserDefaults(suiteName: Self.bookmarksGroup)

    func clear() {
        guard let defaults else { return }
        defaults.dictionaryRepresentation().keys.forEach(defaults.removeObject(forKey:))
    }
}
