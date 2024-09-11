import Defaults
import SwiftyJSON

final class BrowsingSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "showHome": Defaults[.showHome],
            "showOpenActionsInHome": Defaults[.showOpenActionsInHome],
            "showQueueInHome": Defaults[.showQueueInHome],
            "showFavoritesInHome": Defaults[.showFavoritesInHome],
            "favorites": Defaults[.favorites].compactMap { jsonFromString(FavoriteItem.bridge.serialize($0)) },
            "widgetsSettings": Defaults[.widgetsSettings].compactMap { widgetSettingsJSON($0) },
            "startupSection": Defaults[.startupSection].rawValue,
            "showSearchSuggestions": Defaults[.showSearchSuggestions],
            "visibleSections": Defaults[.visibleSections].compactMap { $0.rawValue },
            "showOpenActionsToolbarItem": Defaults[.showOpenActionsToolbarItem],
            "accountPickerDisplaysAnonymousAccounts": Defaults[.accountPickerDisplaysAnonymousAccounts],
            "showUnwatchedFeedBadges": Defaults[.showUnwatchedFeedBadges],
            "expandChannelDescription": Defaults[.expandChannelDescription],
            "keepChannelsWithUnwatchedFeedOnTop": Defaults[.keepChannelsWithUnwatchedFeedOnTop],
            "showChannelAvatarInChannelsLists": Defaults[.showChannelAvatarInChannelsLists],
            "showChannelAvatarInVideosListing": Defaults[.showChannelAvatarInVideosListing],
            "playerButtonSingleTapGesture": Defaults[.playerButtonSingleTapGesture].rawValue,
            "playerButtonDoubleTapGesture": Defaults[.playerButtonDoubleTapGesture].rawValue,
            "playerButtonShowsControlButtonsWhenMinimized": Defaults[.playerButtonShowsControlButtonsWhenMinimized],
            "playerButtonIsExpanded": Defaults[.playerButtonIsExpanded],
            "playerBarMaxWidth": Defaults[.playerBarMaxWidth],
            "channelOnThumbnail": Defaults[.channelOnThumbnail],
            "timeOnThumbnail": Defaults[.timeOnThumbnail],
            "roundedThumbnails": Defaults[.roundedThumbnails],
            "thumbnailsQuality": Defaults[.thumbnailsQuality].rawValue
        ]
    }

    override var platformJSON: JSON {
        var export = JSON()

        #if os(iOS)
            export["showDocuments"].bool = Defaults[.showDocuments]
            export["lockPortraitWhenBrowsing"].bool = Defaults[.lockPortraitWhenBrowsing]
        #endif

        #if !os(tvOS)
            export["accountPickerDisplaysUsername"].bool = Defaults[.accountPickerDisplaysUsername]
        #endif

        return export
    }

    private func widgetSettingsJSON(_ settings: WidgetSettings) -> JSON {
        var json = JSON()
        json.dictionaryObject = WidgetSettingsBridge().serialize(settings)
        return json
    }
}
