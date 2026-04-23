import Foundation

enum AppGroup {
    static let identifier = "group.stream.yattee.app.shared"

    /// UserDefaults key holding an ordered [String] of enabled TopShelfSection raw values.
    static let enabledSectionsKey = "topShelf.enabledSections"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
