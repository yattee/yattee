//
//  PanelSettings.swift
//  Yattee
//
//  Preset-backed configuration for the player details panel pages.
//

import Foundation

// MARK: - Panel Page Type

/// A page that can be shown inside the player details panel.
enum PanelPageType: String, Codable, CaseIterable, Sendable {
    case info
    case comments
    case related
    case chapters
    case queue
    case tracks

    /// Localized display name shown in the page bar and settings.
    var displayName: String {
        switch self {
        case .info:
            return String(localized: "panel.page.info")
        case .comments:
            return String(localized: "player.comments")
        case .related:
            return String(localized: "panel.page.related")
        case .chapters:
            return String(localized: "player.chapters")
        case .queue:
            return String(localized: "panel.page.queue")
        case .tracks:
            return String(localized: "panel.page.tracks")
        }
    }

    /// SF Symbol used in the page bar and settings.
    var systemImage: String {
        switch self {
        case .info:
            return "info.circle"
        case .comments:
            return "bubble.left.and.bubble.right"
        case .related:
            return "rectangle.stack.badge.play"
        case .chapters:
            return "list.bullet.rectangle"
        case .queue:
            return "list.bullet"
        case .tracks:
            return "slider.horizontal.3"
        }
    }
}

// MARK: - Panel Region

/// Region a page is assigned to in the corner layout.
/// `primary` is the right column in corner mode and the only panel elsewhere;
/// the assignment is ignored outside corner mode.
enum PanelRegion: String, Codable, Sendable {
    case primary
    case belowVideo
}

// MARK: - Layout Mode

/// How the details panel is laid out on iPad/macOS.
/// Corner mode automatically falls back to stacked when the window is narrow.
enum PanelLayoutMode: String, Codable, Sendable {
    case stacked
    case corner
}

// MARK: - Default Visibility

/// Default panel visibility when the player opens on iPad/macOS.
enum PanelDefaultVisibility: String, Codable, Sendable {
    case hidden
    case visible
    case remember
}

// MARK: - Per-Page Settings

/// Element toggles for the info page. Optionals fall back to defaults so
/// future fields stay compatible with old saved presets.
struct InfoPageSettings: Codable, Hashable, Sendable {
    var showStatsRow: Bool?
    var showChannelRow: Bool?
    var showDescription: Bool?
    var descriptionCollapsedLines: Int?

    var effectiveShowStatsRow: Bool { showStatsRow ?? true }
    var effectiveShowChannelRow: Bool { showChannelRow ?? true }
    var effectiveShowDescription: Bool { showDescription ?? true }
}

/// Element toggles for the comments page.
struct CommentsPageSettings: Codable, Hashable, Sendable {
    var showAvatars: Bool?

    var effectiveShowAvatars: Bool { showAvatars ?? true }
}

/// Element toggles for the related videos page.
struct RelatedPageSettings: Codable, Hashable, Sendable {
    var showThumbnails: Bool?

    var effectiveShowThumbnails: Bool { showThumbnails ?? true }
}

/// Element toggles for the queue page.
struct QueuePageSettings: Codable, Hashable, Sendable {
    var showHistory: Bool?

    var effectiveShowHistory: Bool { showHistory ?? true }
}

/// Element toggles for the chapters page.
struct ChaptersPageSettings: Codable, Hashable, Sendable {
    var showThumbnails: Bool?

    var effectiveShowThumbnails: Bool { showThumbnails ?? true }
}

/// Element toggles for the tracks page.
struct TracksPageSettings: Codable, Hashable, Sendable {
    var showQuality: Bool?
    var showAudio: Bool?
    var showSubtitles: Bool?
    var showRate: Bool?
}

/// Typed per-page settings payload. Uses the same discriminator pattern as
/// `ButtonSettings`; an unknown discriminator from a future app version
/// decodes to `nil` at the configuration level so the pages array never
/// fails to decode as a whole.
enum PanelPageSettings: Codable, Hashable, Sendable {
    case info(InfoPageSettings)
    case comments(CommentsPageSettings)
    case related(RelatedPageSettings)
    case chapters(ChaptersPageSettings)
    case queue(QueuePageSettings)
    case tracks(TracksPageSettings)

    private enum CodingKeys: String, CodingKey {
        case type
        case info
        case comments
        case related
        case chapters
        case queue
        case tracks
    }

    private enum SettingsType: String, Codable {
        case info
        case comments
        case related
        case chapters
        case queue
        case tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SettingsType.self, forKey: .type)

        switch type {
        case .info:
            self = .info(try container.decode(InfoPageSettings.self, forKey: .info))
        case .comments:
            self = .comments(try container.decode(CommentsPageSettings.self, forKey: .comments))
        case .related:
            self = .related(try container.decode(RelatedPageSettings.self, forKey: .related))
        case .chapters:
            self = .chapters(try container.decode(ChaptersPageSettings.self, forKey: .chapters))
        case .queue:
            self = .queue(try container.decode(QueuePageSettings.self, forKey: .queue))
        case .tracks:
            self = .tracks(try container.decode(TracksPageSettings.self, forKey: .tracks))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .info(let settings):
            try container.encode(SettingsType.info, forKey: .type)
            try container.encode(settings, forKey: .info)
        case .comments(let settings):
            try container.encode(SettingsType.comments, forKey: .type)
            try container.encode(settings, forKey: .comments)
        case .related(let settings):
            try container.encode(SettingsType.related, forKey: .type)
            try container.encode(settings, forKey: .related)
        case .chapters(let settings):
            try container.encode(SettingsType.chapters, forKey: .type)
            try container.encode(settings, forKey: .chapters)
        case .queue(let settings):
            try container.encode(SettingsType.queue, forKey: .type)
            try container.encode(settings, forKey: .queue)
        case .tracks(let settings):
            try container.encode(SettingsType.tracks, forKey: .type)
            try container.encode(settings, forKey: .tracks)
        }
    }
}

// MARK: - Page Configuration

/// One page entry in the ordered panel pages list.
struct PanelPageConfiguration: Codable, Hashable, Sendable, Identifiable {
    var id: PanelPageType { pageType }

    var pageType: PanelPageType
    var isEnabled: Bool
    var region: PanelRegion
    var settings: PanelPageSettings?

    init(
        pageType: PanelPageType,
        isEnabled: Bool = true,
        region: PanelRegion = .primary,
        settings: PanelPageSettings? = nil
    ) {
        self.pageType = pageType
        self.isEnabled = isEnabled
        self.region = region
        self.settings = settings
    }

    /// Info page settings when this is an info page, defaults otherwise.
    var infoSettings: InfoPageSettings {
        if case .info(let settings) = settings { return settings }
        return InfoPageSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case pageType
        case isEnabled
        case region
        case settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageType = try container.decode(PanelPageType.self, forKey: .pageType)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        region = try container.decodeIfPresent(PanelRegion.self, forKey: .region) ?? .primary
        // Unknown discriminators from future versions decode to nil (defaults)
        // instead of corrupting the pages array.
        settings = try? container.decodeIfPresent(PanelPageSettings.self, forKey: .settings)
    }
}

// MARK: - Panel Settings

/// Complete details panel configuration stored on a `PlayerControlsLayout`.
struct PanelSettings: Codable, Hashable, Sendable {
    /// One ordered list of pages: the single source of truth for order,
    /// enablement, and (corner mode) region assignment.
    var pages: [PanelPageConfiguration]

    /// Layout mode on iPad/macOS. Effective default: `.stacked`.
    var layoutMode: PanelLayoutMode?

    /// Default panel visibility when the player opens. Effective default:
    /// `.hidden` (today's behavior).
    var defaultVisibility: PanelDefaultVisibility?

    /// Whether the page bar shows labels next to icons.
    var showPageBarLabels: Bool?

    init(
        pages: [PanelPageConfiguration],
        layoutMode: PanelLayoutMode? = nil,
        defaultVisibility: PanelDefaultVisibility? = nil,
        showPageBarLabels: Bool? = nil
    ) {
        self.pages = pages
        self.layoutMode = layoutMode
        self.defaultVisibility = defaultVisibility
        self.showPageBarLabels = showPageBarLabels
    }

    static let `default` = PanelSettings(pages: [
        PanelPageConfiguration(pageType: .info, region: .belowVideo),
        PanelPageConfiguration(pageType: .comments, region: .belowVideo),
        PanelPageConfiguration(pageType: .related, region: .primary),
        PanelPageConfiguration(pageType: .chapters, region: .primary),
        PanelPageConfiguration(pageType: .queue, region: .primary),
        PanelPageConfiguration(pageType: .tracks, isEnabled: false, region: .primary),
    ])

    var effectiveLayoutMode: PanelLayoutMode { layoutMode ?? .stacked }
    var effectiveDefaultVisibility: PanelDefaultVisibility { defaultVisibility ?? .hidden }
    var effectiveShowPageBarLabels: Bool { showPageBarLabels ?? true }

    /// Pages the panel should offer, in order. Pass a region to filter for
    /// corner mode; `nil` returns enabled pages from all regions.
    func enabledPages(in region: PanelRegion? = nil) -> [PanelPageConfiguration] {
        normalizedPages.filter { page in
            guard page.isEnabled else { return false }
            if let region { return page.region == region }
            return true
        }
    }

    /// The pages list with any page types this app version knows about but
    /// the stored list is missing appended as disabled, so newly introduced
    /// pages surface in settings after an update.
    var normalizedPages: [PanelPageConfiguration] {
        var result = pages
        let known = Set(pages.map(\.pageType))
        for pageType in PanelPageType.allCases where !known.contains(pageType) {
            result.append(PanelPageConfiguration(pageType: pageType, isEnabled: false))
        }
        return result
    }

    /// Whether a page type is enabled in this configuration.
    func isPageEnabled(_ pageType: PanelPageType) -> Bool {
        enabledPages().contains { $0.pageType == pageType }
    }

    private enum CodingKeys: String, CodingKey {
        case pages
        case layoutMode
        case defaultVisibility
        case showPageBarLabels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Lenient element decoding: a page entry with an unknown pageType
        // (from a future app version) is dropped instead of failing the
        // whole settings decode.
        var pagesContainer = try container.nestedUnkeyedContainer(forKey: .pages)
        var decodedPages: [PanelPageConfiguration] = []
        while !pagesContainer.isAtEnd {
            if let page = try? pagesContainer.decode(PanelPageConfiguration.self) {
                decodedPages.append(page)
            } else {
                // Skip the undecodable element to keep the container advancing.
                _ = try? pagesContainer.decode(AnyDecodableValue.self)
            }
        }
        pages = decodedPages
        layoutMode = try? container.decodeIfPresent(PanelLayoutMode.self, forKey: .layoutMode)
        defaultVisibility = try? container.decodeIfPresent(PanelDefaultVisibility.self, forKey: .defaultVisibility)
        showPageBarLabels = try container.decodeIfPresent(Bool.self, forKey: .showPageBarLabels)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
        try container.encodeIfPresent(layoutMode, forKey: .layoutMode)
        try container.encodeIfPresent(defaultVisibility, forKey: .defaultVisibility)
        try container.encodeIfPresent(showPageBarLabels, forKey: .showPageBarLabels)
    }
}

/// Consumes any JSON value during lenient array decoding.
private struct AnyDecodableValue: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        if (try? container.decode(String.self)) != nil { return }
        if (try? container.decode([String: AnyDecodableValue].self)) != nil { return }
        if (try? container.decode([AnyDecodableValue].self)) != nil { return }
    }
}
