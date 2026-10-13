//
//  PanelSettings.swift
//  Yattee
//
//  Preset-backed configuration for the player details panel pages.
//

import Foundation
import SwiftUI

// MARK: - Panel Page Type

/// A page that can be shown inside the player details panel.
enum PanelPageType: String, Codable, CaseIterable, Sendable {
    case info
    case comments
    case related
    case chapters
    case queue

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
        }
    }

    /// The panel settings version when this page type was added.
    /// Used for showing "NEW" badges on recently added pages.
    var versionAdded: Int {
        // All initial pages shipped together; bump for future page types.
        return 1
    }

    /// Pages added after this version show a "NEW" badge in settings.
    /// Raise it together with the release that introduces a new page type.
    static let newBadgeThresholdVersion = 1

    /// Whether this page should carry a "NEW" badge in settings.
    var isRecentlyAdded: Bool {
        versionAdded > Self.newBadgeThresholdVersion
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
        }
    }
}

// MARK: - Panel Region

/// Region a page is assigned to in the corner layout.
/// `primary` is the right column in corner mode and the only panel elsewhere;
/// the assignment is ignored outside corner mode.
///
/// The below-video host is the portrait info panel, not a page host: only
/// `.info` can live there, plus `.comments` as the panel's pill (iOS). Every
/// other page is clamped to `.primary` by `PanelSettings.normalizedPages`, and
/// settings expose the choice as one `PanelBelowVideoContent` picker.
enum PanelRegion: String, Codable, CaseIterable, Sendable {
    case primary
    case belowVideo

    /// Localized name for the pages list.
    var displayName: String {
        switch self {
        case .primary:
            return String(localized: "panel.region.primary")
        case .belowVideo:
            return String(localized: "panel.region.belowVideo")
        }
    }
}

/// What the corner layout shows below the video: the three layouts the
/// below-video host can actually render. Stored as the info/comments page
/// regions (see `PanelSettings.belowVideoContent`).
enum PanelBelowVideoContent: String, CaseIterable, Sendable {
    /// Video fills the left column; every page sits in the side column.
    case nothing
    /// The info panel below the video; comments join the side column.
    case info
    /// The info panel with the comments pill below the video (iOS only).
    case infoAndComments

    /// Localized name for the settings picker.
    var displayName: String {
        switch self {
        case .nothing:
            return String(localized: "panel.belowVideo.nothing")
        case .info:
            return String(localized: "panel.belowVideo.info")
        case .infoAndComments:
            return String(localized: "panel.belowVideo.infoAndComments")
        }
    }

    /// Options this platform can render: the comments pill lives on the
    /// iOS portrait panel only.
    static var availableCases: [PanelBelowVideoContent] {
        PanelSettings.supportsBelowVideoComments ? allCases : [.nothing, .info]
    }
}

// MARK: - Layout Mode

/// How the details panel is laid out on iPad/macOS.
/// Corner mode automatically falls back to stacked when the window is narrow.
enum PanelLayoutMode: String, Codable, CaseIterable, Sendable {
    case stacked
    case corner

    /// Localized name for the settings picker.
    var displayName: String {
        switch self {
        case .stacked:
            return String(localized: "panel.layoutMode.stacked")
        case .corner:
            return String(localized: "panel.layoutMode.corner")
        }
    }
}

// MARK: - Default Visibility

/// Which player layout a panel default applies to: portrait (iPhone/iPad
/// upright) or landscape (wide layout: iPhone/iPad rotated, macOS always).
enum PanelOrientation: Sendable {
    case portrait
    case landscape
}

/// Default panel visibility when the player opens, configured per
/// orientation (see `PanelSettings.effectiveDefaultVisibility(for:)`).
enum PanelDefaultVisibility: String, Codable, CaseIterable, Sendable {
    case hidden
    case visible
    case remember

    /// Resolves the mode to a concrete initial visibility, given the last
    /// user-set visibility for the same orientation.
    func resolve(lastVisible: Bool) -> Bool {
        switch self {
        case .hidden:
            return false
        case .visible:
            return true
        case .remember:
            return lastVisible
        }
    }

    /// Localized name for the settings picker.
    var displayName: String {
        switch self {
        case .hidden:
            return String(localized: "panel.defaultVisibility.hidden")
        case .visible:
            return String(localized: "panel.defaultVisibility.visible")
        case .remember:
            return String(localized: "panel.defaultVisibility.remember")
        }
    }
}

// MARK: - Per-Page Settings

/// Element toggles for the info page. Optionals fall back to defaults so
/// future fields stay compatible with old saved presets.
struct InfoPageSettings: Codable, Hashable, Sendable {
    var showStatsRow: Bool?
    var showChannelRow: Bool?
    var showDescription: Bool?
    /// Lines shown while the description is collapsed (inline-sections hosts).
    var descriptionCollapsedLines: Int?
    /// Whether the description starts expanded instead of collapsed.
    var descriptionExpandedByDefault: Bool?

    static let defaultDescriptionCollapsedLines = 3
    static let descriptionCollapsedLinesRange = 1...10

    var effectiveShowStatsRow: Bool { showStatsRow ?? true }
    var effectiveShowChannelRow: Bool { showChannelRow ?? true }
    var effectiveShowDescription: Bool { showDescription ?? true }
    var effectiveDescriptionExpandedByDefault: Bool { descriptionExpandedByDefault ?? false }
    var effectiveDescriptionCollapsedLines: Int {
        let range = Self.descriptionCollapsedLinesRange
        return min(max(descriptionCollapsedLines ?? Self.defaultDescriptionCollapsedLines, range.lowerBound), range.upperBound)
    }
}

// MARK: - Comments Pill Mode

/// Controls how the comments pill is displayed in the player.
/// Stored on the comments page settings (moved from the player pill settings;
/// `PlayerControlsLayout.effectivePanelSettings` migrates the legacy value).
enum CommentsPillMode: String, Codable, Hashable, Sendable, CaseIterable {
    case pill       // Default - shows expanded pill, collapses on scroll
    case button     // Always show collapsed (button-only)
    case disabled   // No button/pill visible

    /// Localized display name for settings UI.
    var displayName: String {
        switch self {
        case .pill:
            return String(localized: "commentsPill.mode.pill")
        case .button:
            return String(localized: "commentsPill.mode.button")
        case .disabled:
            return String(localized: "commentsPill.mode.disabled")
        }
    }

    /// Whether the comments pill should always be collapsed (button mode).
    var alwaysCollapsed: Bool {
        self == .button
    }
}

/// Element toggles for the comments page.
struct CommentsPageSettings: Codable, Hashable, Sendable {
    var showAvatars: Bool?
    /// How the comments pill (portrait/floating panel) is displayed.
    var pillMode: CommentsPillMode?

    var effectiveShowAvatars: Bool { showAvatars ?? true }
    var effectivePillMode: CommentsPillMode { pillMode ?? .pill }
}

/// Element toggles for the related videos page.
struct RelatedPageSettings: Codable, Hashable, Sendable {
    var showThumbnails: Bool?
    /// Whether the inline section (iPhone, iPad portrait) starts expanded.
    var expandedByDefault: Bool?

    var effectiveShowThumbnails: Bool { showThumbnails ?? true }
    var effectiveExpandedByDefault: Bool { expandedByDefault ?? true }
}

/// Element toggles for the queue page.
struct QueuePageSettings: Codable, Hashable, Sendable {
    var showHistory: Bool?
    /// Whether the playing video is listed between history and the queue.
    /// Off by default: the player itself already shows it.
    var showNowPlaying: Bool?

    var effectiveShowHistory: Bool { showHistory ?? true }
    var effectiveShowNowPlaying: Bool { showNowPlaying ?? false }
}

/// Element toggles for the chapters page.
struct ChaptersPageSettings: Codable, Hashable, Sendable {
    var showThumbnails: Bool?
    /// Whether the inline section (iPhone, iPad portrait) starts expanded.
    var expandedByDefault: Bool?

    var effectiveShowThumbnails: Bool { showThumbnails ?? true }
    var effectiveExpandedByDefault: Bool { expandedByDefault ?? true }
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

    private enum CodingKeys: String, CodingKey {
        case type
        case info
        case comments
        case related
        case chapters
        case queue
    }

    private enum SettingsType: String, Codable {
        case info
        case comments
        case related
        case chapters
        case queue
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

    /// Comments page settings when set, defaults otherwise.
    var commentsSettings: CommentsPageSettings {
        if case .comments(let settings) = settings { return settings }
        return CommentsPageSettings()
    }

    /// Related page settings when set, defaults otherwise.
    var relatedSettings: RelatedPageSettings {
        if case .related(let settings) = settings { return settings }
        return RelatedPageSettings()
    }

    /// Chapters page settings when set, defaults otherwise.
    var chaptersSettings: ChaptersPageSettings {
        if case .chapters(let settings) = settings { return settings }
        return ChaptersPageSettings()
    }

    /// Queue page settings when set, defaults otherwise.
    var queueSettings: QueuePageSettings {
        if case .queue(let settings) = settings { return settings }
        return QueuePageSettings()
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

    /// Legacy single default visibility from before the per-orientation
    /// split. Still decoded so older presets keep their choice: it seeds both
    /// orientations until they are set individually. Not written by the UI.
    var defaultVisibility: PanelDefaultVisibility?

    /// Default panel visibility when the player opens in portrait. Effective
    /// default: the legacy value, else `.visible`.
    var portraitDefaultVisibility: PanelDefaultVisibility?

    /// Default panel visibility when the player opens in landscape (the wide
    /// layout, including macOS). Effective default: the legacy value, else
    /// `.hidden`.
    var landscapeDefaultVisibility: PanelDefaultVisibility?

    /// Whether the page bar shows labels next to icons.
    var showPageBarLabels: Bool?

    /// Which side the details panel sits on in the standard wide layout on
    /// iPad/macOS. iPhone ignores it (always right). Effective default: `.right`.
    var wideLayoutSide: FloatingPanelSide?

    init(
        pages: [PanelPageConfiguration],
        layoutMode: PanelLayoutMode? = nil,
        defaultVisibility: PanelDefaultVisibility? = nil,
        portraitDefaultVisibility: PanelDefaultVisibility? = nil,
        landscapeDefaultVisibility: PanelDefaultVisibility? = nil,
        showPageBarLabels: Bool? = nil,
        wideLayoutSide: FloatingPanelSide? = nil
    ) {
        self.pages = pages
        self.layoutMode = layoutMode
        self.defaultVisibility = defaultVisibility
        self.portraitDefaultVisibility = portraitDefaultVisibility
        self.landscapeDefaultVisibility = landscapeDefaultVisibility
        self.showPageBarLabels = showPageBarLabels
        self.wideLayoutSide = wideLayoutSide
    }

    /// In-memory cache of the active preset's panel settings, refreshed by the
    /// player whenever the layout loads. Lets synchronous appear paths (e.g.
    /// default-visibility resets) read the last known value before the async
    /// layout fetch completes.
    nonisolated(unsafe) static var cached: PanelSettings = .default

    static let `default` = PanelSettings(pages: [
        PanelPageConfiguration(pageType: .info, region: .belowVideo),
        PanelPageConfiguration(pageType: .comments, region: .belowVideo),
        PanelPageConfiguration(pageType: .related, region: .primary),
        PanelPageConfiguration(pageType: .chapters, region: .primary),
        PanelPageConfiguration(pageType: .queue, region: .primary),
    ])

    /// Panel settings of the built-in presets: the default pages in the
    /// corner layout. The player still falls back to the stacked layout where
    /// the corner layout doesn't fit (iPhone, iPad portrait, narrow windows).
    /// `default` stays stacked so presets saved without panel settings keep
    /// the layout they had.
    static let builtInDefault: PanelSettings = {
        var settings = PanelSettings.default
        settings.layoutMode = .corner
        return settings
    }()

    var effectiveLayoutMode: PanelLayoutMode { layoutMode ?? .stacked }

    /// The default visibility for an orientation: its own value, else the
    /// legacy single value, else portrait visible / landscape hidden — except
    /// landscape in the corner layout on a device that can show it, where the
    /// panels are the point of the layout and open visible.
    func effectiveDefaultVisibility(for orientation: PanelOrientation) -> PanelDefaultVisibility {
        effectiveDefaultVisibility(for: orientation, cornerLayoutFits: Self.canHostCornerLayout)
    }

    /// Same as `effectiveDefaultVisibility(for:)`, but the corner fallback
    /// follows whether the corner layout fits the current screen — the iPhone
    /// Duo exterior display can't host it and falls back to the floating
    /// widescreen panel, which must not open by default.
    func effectiveDefaultVisibility(for orientation: PanelOrientation, cornerLayoutFits: Bool) -> PanelDefaultVisibility {
        switch orientation {
        case .portrait:
            return portraitDefaultVisibility ?? defaultVisibility ?? .visible
        case .landscape:
            let fallback: PanelDefaultVisibility =
                effectiveLayoutMode == .corner && cornerLayoutFits ? .visible : .hidden
            return landscapeDefaultVisibility ?? defaultVisibility ?? fallback
        }
    }

    /// Whether this device has a screen the corner layout fits on: iPad,
    /// macOS, and foldable iPhones (interior display).
    static var canHostCornerLayout: Bool {
        #if os(macOS)
        return true
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad || deviceHasHinge
        #else
        return false
        #endif
    }

    private static let deviceHasHingeKey = "deviceHasHinge"

    /// Whether a hinge has ever been reported on this device (foldable
    /// iPhone). Hinge state only arrives through views, so the hinge
    /// observers record it here for code that runs without one. Local only.
    static var deviceHasHinge: Bool {
        get { UserDefaults.standard.bool(forKey: deviceHasHingeKey) }
        set {
            guard newValue != deviceHasHinge else { return }
            UserDefaults.standard.set(newValue, forKey: deviceHasHingeKey)
        }
    }

    /// Sets the default visibility for one orientation.
    mutating func setDefaultVisibility(_ visibility: PanelDefaultVisibility, for orientation: PanelOrientation) {
        switch orientation {
        case .portrait:
            portraitDefaultVisibility = visibility
        case .landscape:
            landscapeDefaultVisibility = visibility
        }
    }
    var effectiveShowPageBarLabels: Bool { showPageBarLabels ?? true }
    var effectiveWideLayoutSide: FloatingPanelSide { wideLayoutSide ?? .right }

    /// Pages the panel should offer, in order. Pass a region to filter for
    /// corner mode; `nil` returns enabled pages from all regions.
    func enabledPages(in region: PanelRegion? = nil) -> [PanelPageConfiguration] {
        normalizedPages.filter { page in
            guard page.isEnabled else { return false }
            if let region { return page.region == region }
            return true
        }
    }

    /// The page that is always first and always enabled in every layout:
    /// the video info is the panel's anchor (title under the drag handle,
    /// collapsible description, comments pill), so it cannot be moved below
    /// other pages or switched off. Its element toggles remain configurable.
    static let pinnedPageType: PanelPageType = .info

    /// Page types the below-video host can render: the info panel itself and
    /// comments as its pill. Other types assigned `.belowVideo` (older
    /// presets) are clamped back to the side column.
    static let belowVideoHostablePageTypes: Set<PanelPageType> = [.info, .comments]

    /// Whether this platform renders comments below the video (the comments
    /// pill on the portrait info panel exists on iOS only).
    static var supportsBelowVideoComments: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    /// The pages list with any page types this app version knows about but
    /// the stored list is missing appended as disabled, so newly introduced
    /// pages surface in settings after an update, the pinned page forced
    /// first and enabled (older presets may have stored it elsewhere), and
    /// regions clamped to what the corner layout can host: only info and
    /// comments may sit below the video, comments only together with info.
    var normalizedPages: [PanelPageConfiguration] {
        var result = pages
        let known = Set(pages.map(\.pageType))
        for pageType in PanelPageType.allCases where !known.contains(pageType) {
            result.append(PanelPageConfiguration(pageType: pageType, isEnabled: false))
        }

        if let pinnedIndex = result.firstIndex(where: { $0.pageType == Self.pinnedPageType }) {
            var pinned = result.remove(at: pinnedIndex)
            pinned.isEnabled = true
            result.insert(pinned, at: 0)
        }

        let infoBelowVideo = result.contains { $0.pageType == .info && $0.region == .belowVideo }
        for index in result.indices where result[index].region == .belowVideo {
            let type = result[index].pageType
            let hostable = Self.belowVideoHostablePageTypes.contains(type)
                && (type != .comments || infoBelowVideo)
            if !hostable {
                result[index].region = .primary
            }
        }
        return result
    }

    /// The stored below-video choice, derived from the info/comments regions.
    /// Platform-agnostic so presets keep their value across devices; use
    /// `effectiveBelowVideoContent` for what this device renders.
    var belowVideoContent: PanelBelowVideoContent {
        get {
            guard configuration(for: .info)?.region == .belowVideo else { return .nothing }
            return configuration(for: .comments)?.region == .belowVideo ? .infoAndComments : .info
        }
        set {
            normalize()
            let infoRegion: PanelRegion = newValue == .nothing ? .primary : .belowVideo
            let commentsRegion: PanelRegion = newValue == .infoAndComments ? .belowVideo : .primary
            for index in pages.indices {
                switch pages[index].pageType {
                case .info: pages[index].region = infoRegion
                case .comments: pages[index].region = commentsRegion
                default: pages[index].region = .primary
                }
            }
        }
    }

    /// The below-video content this platform renders: comments fall back to
    /// the side column where the pill does not exist.
    var effectiveBelowVideoContent: PanelBelowVideoContent {
        let stored = belowVideoContent
        if stored == .infoAndComments, !Self.supportsBelowVideoComments { return .info }
        return stored
    }

    /// Where the corner layout actually places a page on this platform.
    func effectiveRegion(for pageType: PanelPageType) -> PanelRegion {
        switch (pageType, effectiveBelowVideoContent) {
        case (.info, .info), (.info, .infoAndComments), (.comments, .infoAndComments):
            return .belowVideo
        default:
            return .primary
        }
    }

    /// Page types the info page can render as collapsible inline sections
    /// below the description (iPhone, and the stacked iPad portrait panel).
    static let inlineSectionTypes: Set<PanelPageType> = [.chapters, .related]

    /// iPhone has no page switcher: every host renders one info page with
    /// inline sections, so settings talk about "sections" rather than "pages".
    static var isSectionsOnlyDevice: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    /// Page types the settings list hides on this device because the panel
    /// never renders them as pages: iPhone shows only the info page with
    /// inline sections, so queue has no effect there and comments live on
    /// the pill/overlay (configured in their own settings group).
    static var hiddenSettingsPageTypes: Set<PanelPageType> {
        isSectionsOnlyDevice ? [.queue, .comments] : []
    }

    /// Enabled pages an inline-sections host renders below the video info,
    /// in configured order, with their per-page element settings.
    func inlineSections(in region: PanelRegion? = nil) -> [PanelPageConfiguration] {
        enabledPages(in: region).filter { Self.inlineSectionTypes.contains($0.pageType) }
    }

    /// Whether a page type is enabled in this configuration.
    func isPageEnabled(_ pageType: PanelPageType) -> Bool {
        enabledPages().contains { $0.pageType == pageType }
    }

    /// The comments pill mode from the comments page settings.
    var commentsPillMode: CommentsPillMode {
        configuration(for: .comments)?.commentsSettings.effectivePillMode ?? .pill
    }

    /// Whether comment rows show author avatars (comments page setting),
    /// honored by the comments page and the pill overlay alike.
    var commentsShowAvatars: Bool {
        configuration(for: .comments)?.commentsSettings.effectiveShowAvatars ?? true
    }

    /// Whether comments should be loaded from the API: needed by the comments
    /// page (when enabled) and by the pill (unless disabled).
    var shouldLoadComments: Bool {
        isPageEnabled(.comments) || commentsPillMode != .disabled
    }

    /// The stored configuration for a page type, if present.
    func configuration(for pageType: PanelPageType) -> PanelPageConfiguration? {
        normalizedPages.first { $0.pageType == pageType }
    }

    // MARK: - Mutations (settings UI)

    /// Replaces the stored pages with the normalized list so mutations by
    /// index operate on the same list the UI displays.
    mutating func normalize() {
        pages = normalizedPages
    }

    /// Enables or disables a page. The pinned page ignores this.
    mutating func setEnabled(_ isEnabled: Bool, for pageType: PanelPageType) {
        normalize()
        guard pageType != Self.pinnedPageType,
              let index = pages.firstIndex(where: { $0.pageType == pageType })
        else { return }
        pages[index].isEnabled = isEnabled
    }

    /// Reorders pages by index in the normalized list. The pinned page snaps
    /// back to the front afterwards, so moving it (or moving another page
    /// above it) has no effect.
    mutating func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        normalize()
        pages.move(fromOffsets: source, toOffset: destination)
        normalize()
    }

    /// Reorders the subset of pages a settings list displays (offsets are
    /// relative to `visible`, in its current order). Pages the list hides
    /// keep their slots; the pinned page stays first.
    mutating func moveVisiblePages(
        _ visible: [PanelPageType],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        normalize()
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)

        let byType = Dictionary(uniqueKeysWithValues: pages.map { ($0.pageType, $0) })
        let visibleSet = Set(visible)
        var next = reordered.makeIterator()
        pages = pages.map { page in
            guard visibleSet.contains(page.pageType),
                  let type = next.next(),
                  let replacement = byType[type]
            else { return page }
            return replacement
        }
        normalize()
    }

    mutating func updateSettings(_ newSettings: PanelPageSettings?, for pageType: PanelPageType) {
        normalize()
        guard let index = pages.firstIndex(where: { $0.pageType == pageType }) else { return }
        pages[index].settings = newSettings
    }

    private enum CodingKeys: String, CodingKey {
        case pages
        case layoutMode
        case defaultVisibility
        case portraitDefaultVisibility
        case landscapeDefaultVisibility
        case showPageBarLabels
        case wideLayoutSide
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
        portraitDefaultVisibility = try? container.decodeIfPresent(PanelDefaultVisibility.self, forKey: .portraitDefaultVisibility)
        landscapeDefaultVisibility = try? container.decodeIfPresent(PanelDefaultVisibility.self, forKey: .landscapeDefaultVisibility)
        showPageBarLabels = try container.decodeIfPresent(Bool.self, forKey: .showPageBarLabels)
        wideLayoutSide = try? container.decodeIfPresent(FloatingPanelSide.self, forKey: .wideLayoutSide)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pages, forKey: .pages)
        try container.encodeIfPresent(layoutMode, forKey: .layoutMode)
        try container.encodeIfPresent(defaultVisibility, forKey: .defaultVisibility)
        try container.encodeIfPresent(portraitDefaultVisibility, forKey: .portraitDefaultVisibility)
        try container.encodeIfPresent(landscapeDefaultVisibility, forKey: .landscapeDefaultVisibility)
        try container.encodeIfPresent(showPageBarLabels, forKey: .showPageBarLabels)
        try container.encodeIfPresent(wideLayoutSide, forKey: .wideLayoutSide)
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
