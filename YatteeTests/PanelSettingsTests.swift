//
//  PanelSettingsTests.swift
//  YatteeTests
//
//  Tests for details panel settings model (Codable compatibility).
//

import Foundation
import Testing
@testable import Yattee

@Suite("Panel Settings Tests")
struct PanelSettingsTests {
    private func roundTrip(_ settings: PanelSettings) throws -> PanelSettings {
        let encoded = try JSONEncoder().encode(settings)
        return try JSONDecoder().decode(PanelSettings.self, from: encoded)
    }

    // MARK: - Round Trip

    @Test("Default settings round-trip")
    func defaultRoundTrip() throws {
        let decoded = try roundTrip(.default)
        #expect(decoded == PanelSettings.default)
    }

    @Test("Customized settings round-trip")
    func customizedRoundTrip() throws {
        var settings = PanelSettings.default
        settings.layoutMode = .corner
        settings.defaultVisibility = .remember
        settings.showPageBarLabels = false
        settings.setEnabled(false, for: .related)
        settings.movePages(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        settings.updateSettings(
            .info(InfoPageSettings(showStatsRow: false, showDescription: false)),
            for: .info
        )

        let decoded = try roundTrip(settings)
        #expect(decoded == settings)
        #expect(decoded.effectiveLayoutMode == .corner)
        #expect(decoded.effectiveDefaultVisibility == .remember)
        #expect(decoded.effectiveShowPageBarLabels == false)
        #expect(!decoded.isPageEnabled(.related))

        let info = decoded.configuration(for: .info)?.infoSettings
        #expect(info?.effectiveShowStatsRow == false)
        #expect(info?.effectiveShowDescription == false)
        #expect(info?.effectiveShowChannelRow == true)
    }

    @Test("Inline sections follow the configured page order and enablement")
    func inlineSectionsFollowOrder() {
        var settings = PanelSettings.default
        // Default order: info, comments, related, chapters, queue
        #expect(settings.inlineSections().map(\.pageType) == [.related, .chapters])

        // Move chapters (index 3) above related (index 2)
        settings.movePages(fromOffsets: IndexSet(integer: 3), toOffset: 2)
        #expect(settings.inlineSections().map(\.pageType) == [.chapters, .related])

        settings.setEnabled(false, for: .related)
        #expect(settings.inlineSections().map(\.pageType) == [.chapters])

        settings.updateSettings(.chapters(ChaptersPageSettings(showThumbnails: false)), for: .chapters)
        #expect(settings.inlineSections().first?.chaptersSettings.effectiveShowThumbnails == false)
    }

    @Test("Per-page element settings round-trip for every page type")
    func perPageSettingsRoundTrip() throws {
        var settings = PanelSettings.default
        settings.updateSettings(.comments(CommentsPageSettings(showAvatars: false)), for: .comments)
        settings.updateSettings(.related(RelatedPageSettings(showThumbnails: false)), for: .related)
        settings.updateSettings(.chapters(ChaptersPageSettings(showThumbnails: false)), for: .chapters)
        settings.updateSettings(.queue(QueuePageSettings(showHistory: false)), for: .queue)

        let decoded = try roundTrip(settings)
        #expect(decoded == settings)
        #expect(decoded.configuration(for: .comments)?.commentsSettings.effectiveShowAvatars == false)
        #expect(decoded.configuration(for: .related)?.relatedSettings.effectiveShowThumbnails == false)
        #expect(decoded.configuration(for: .chapters)?.chaptersSettings.effectiveShowThumbnails == false)
        #expect(decoded.configuration(for: .queue)?.queueSettings.effectiveShowHistory == false)
    }

    @Test("Typed accessors fall back to defaults for mismatched payloads")
    func typedAccessorFallbacks() {
        // An info payload read through the comments accessor yields defaults.
        let page = PanelPageConfiguration(
            pageType: .comments,
            settings: .info(InfoPageSettings(showStatsRow: false))
        )
        #expect(page.commentsSettings.effectiveShowAvatars == true)
        #expect(page.queueSettings.effectiveShowHistory == true)
    }

    // MARK: - Backward Compatibility

    @Test("Layout without panelSettings decodes and falls back to default")
    func layoutWithoutPanelSettings() throws {
        let layout = PlayerControlsLayout.default
        var json = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(layout)) as? [String: Any]
        )
        json.removeValue(forKey: "panelSettings")
        let data = try JSONSerialization.data(withJSONObject: json)

        let decoded = try JSONDecoder().decode(PlayerControlsLayout.self, from: data)
        #expect(decoded.panelSettings == nil)
        #expect(decoded.effectivePanelSettings == .default)
    }

    @Test("Minimal page entries decode with defaults")
    func minimalPageEntries() throws {
        let json = """
        { "pages": [ { "pageType": "info" }, { "pageType": "comments" } ] }
        """
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        #expect(decoded.pages.count == 2)
        #expect(decoded.pages.allSatisfy { $0.isEnabled })
        #expect(decoded.pages.allSatisfy { $0.region == .primary })
        #expect(decoded.effectiveLayoutMode == .stacked)
        #expect(decoded.effectiveDefaultVisibility == .hidden)
    }

    // MARK: - Forward Compatibility

    @Test("Unknown page type from a future version is dropped")
    func unknownPageTypeDropped() throws {
        let json = """
        { "pages": [
            { "pageType": "info" },
            { "pageType": "futureHologram", "isEnabled": true },
            { "pageType": "queue" }
        ] }
        """
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        #expect(decoded.pages.map(\.pageType) == [.info, .queue])
    }

    @Test("Unknown settings discriminator decodes to nil settings")
    func unknownSettingsDiscriminator() throws {
        let json = """
        { "pages": [
            { "pageType": "info", "settings": { "type": "futureKind", "futureKind": { "x": 1 } } }
        ] }
        """
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        #expect(decoded.pages.count == 1)
        #expect(decoded.pages.first?.settings == nil)
        // nil settings fall back to defaults
        #expect(decoded.pages.first?.infoSettings.effectiveShowDescription == true)
    }

    @Test("Unknown layoutMode and defaultVisibility decode to nil")
    func unknownEnumValues() throws {
        let json = """
        { "pages": [ { "pageType": "info" } ],
          "layoutMode": "floating",
          "defaultVisibility": "sometimes" }
        """
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        #expect(decoded.layoutMode == nil)
        #expect(decoded.defaultVisibility == nil)
        #expect(decoded.effectiveLayoutMode == .stacked)
        #expect(decoded.effectiveDefaultVisibility == .hidden)
    }

    // MARK: - Normalization

    @Test("Normalized pages append missing types as disabled")
    func normalizedPagesAppendMissing() throws {
        let json = """
        { "pages": [ { "pageType": "info" } ] }
        """
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: Data(json.utf8))
        let normalized = decoded.normalizedPages
        #expect(normalized.count == PanelPageType.allCases.count)
        #expect(normalized.first?.pageType == .info)
        #expect(normalized.dropFirst().allSatisfy { !$0.isEnabled })
    }

    @Test("Enabled pages filter by region")
    func enabledPagesRegionFilter() {
        let settings = PanelSettings.default
        let primary = settings.enabledPages(in: .primary).map(\.pageType)
        let belowVideo = settings.enabledPages(in: .belowVideo).map(\.pageType)
        let all = settings.enabledPages().map(\.pageType)

        #expect(primary == [.related, .chapters, .queue])
        #expect(belowVideo == [.info, .comments])
        #expect(all == [.info, .comments, .related, .chapters, .queue])
    }

    // MARK: - Mutations

    @Test("Disabling and re-enabling a page preserves order")
    func toggleKeepsOrder() {
        var settings = PanelSettings.default
        settings.setEnabled(false, for: .comments)
        #expect(!settings.isPageEnabled(.comments))
        settings.setEnabled(true, for: .comments)
        #expect(settings.pages.map(\.pageType) == PanelSettings.default.pages.map(\.pageType))
    }

    @Test("Region assignment and layout mode round-trip through Codable")
    func regionAndLayoutModeRoundTrip() throws {
        var settings = PanelSettings.default
        settings.layoutMode = .corner
        settings.setRegion(.belowVideo, for: .related)
        #expect(settings.configuration(for: .related)?.region == .belowVideo)
        #expect(settings.enabledPages(in: .primary).map(\.pageType) == [.chapters, .queue])

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PanelSettings.self, from: data)
        #expect(decoded.effectiveLayoutMode == .corner)
        #expect(decoded.configuration(for: .related)?.region == .belowVideo)
    }
}
