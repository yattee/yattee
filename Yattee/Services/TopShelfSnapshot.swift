//
//  TopShelfSnapshot.swift
//  Yattee
//
//  Shared data contract between the main app (writer) and YatteeTopShelf extension (reader).
//  Items are persisted as JSON in the App Group UserDefaults suite under per-section keys.
//

import Foundation

/// A compact representation of a video suitable for a tvOS Top Shelf row.
/// Kept deliberately small — the extension has a tight memory/work budget.
struct TopShelfItem: Codable, Hashable, Sendable {
    let videoID: String
    let title: String
    let authorName: String
    let duration: TimeInterval
    let thumbnailURL: String?
    /// Pre-built `yattee://video/...` URL the extension uses for `displayURL`.
    let deepLinkURL: String
    /// Seconds watched — only set for continue-watching items.
    let progressSeconds: TimeInterval?
}

/// Max items retained per section snapshot. The extension only needs a handful.
enum TopShelfSnapshot {
    static let maxItems = 10

    static func read(section: TopShelfSection, from defaults: UserDefaults = AppGroup.defaults) -> [TopShelfItem] {
        guard let data = defaults.data(forKey: section.snapshotKey),
              let items = try? JSONDecoder().decode([TopShelfItem].self, from: data) else {
            return []
        }
        return items
    }

    static func write(_ items: [TopShelfItem], section: TopShelfSection, to defaults: UserDefaults = AppGroup.defaults) {
        let capped = Array(items.prefix(maxItems))
        if capped.isEmpty {
            defaults.removeObject(forKey: section.snapshotKey)
            return
        }
        guard let data = try? JSONEncoder().encode(capped) else { return }
        defaults.set(data, forKey: section.snapshotKey)
    }
}
