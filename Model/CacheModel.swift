import Foundation
import SwiftyJSON

struct CacheModel {
    static var shared = CacheModel()
    static let bookmarksGroup = "group.stream.yattee.app.bookmarks"

    let bookmarksDefaults = UserDefaults(suiteName: Self.bookmarksGroup)

    func removeAll() {
        guard let bookmarksDefaults else { return }
        bookmarksDefaults.dictionaryRepresentation().keys.forEach(bookmarksDefaults.removeObject(forKey:))
    }
}
