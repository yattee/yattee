import Foundation

// Must stay in sync with Yattee/Services/TopShelfSnapshot.swift.
struct TopShelfItem: Codable, Hashable, Sendable {
    let videoID: String
    let title: String
    let authorName: String
    let duration: TimeInterval
    let thumbnailURL: String?
    let deepLinkURL: String
    let progressSeconds: TimeInterval?
}

enum TopShelfSnapshot {
    static func read(section: TopShelfSection, from defaults: UserDefaults = AppGroup.defaults) -> [TopShelfItem] {
        guard let data = defaults.data(forKey: section.snapshotKey),
              let items = try? JSONDecoder().decode([TopShelfItem].self, from: data) else {
            return []
        }
        return items
    }

    static func enabledSections(from defaults: UserDefaults = AppGroup.defaults) -> [TopShelfSection] {
        guard let raw = defaults.array(forKey: AppGroup.enabledSectionsKey) as? [String] else {
            return TopShelfSection.defaultOrder
        }
        return raw.compactMap { TopShelfSection(rawValue: $0) }
    }
}
