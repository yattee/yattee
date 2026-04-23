import Foundation

enum AppGroup {
    static let identifier = "group.stream.yattee.app.shared"
    static let enabledSectionsKey = "topShelf.enabledSections"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
