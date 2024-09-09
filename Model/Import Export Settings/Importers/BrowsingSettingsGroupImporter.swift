import Defaults
import SwiftyJSON

struct BrowsingSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let showHome = json["showHome"].bool {
            Defaults[.showHome] = showHome
        }

        if let showOpenActionsInHome = json["showOpenActionsInHome"].bool {
            Defaults[.showOpenActionsInHome] = showOpenActionsInHome
        }

        if let showQueueInHome = json["showQueueInHome"].bool {
            Defaults[.showQueueInHome] = showQueueInHome
        }

        if let showFavoritesInHome = json["showFavoritesInHome"].bool {
            Defaults[.showFavoritesInHome] = showFavoritesInHome
        }

        if let favorites = json["favorites"].array {
            for favoriteJSON in favorites {
                if let jsonString = favoriteJSON.rawString(options: []),
                   let item = FavoriteItem.bridge.deserialize(jsonString)
                {
                    FavoritesModel.shared.add(item)
                }
            }
        }

        if let widgetsFavorites = json["widgetsSettings"].array {
            for widgetJSON in widgetsFavorites {
                let dict = widgetJSON.dictionaryValue.mapValues { json in json.stringValue }
                if let item = WidgetSettingsBridge().deserialize(dict) {
                    FavoritesModel.shared.updateWidgetSettings(item)
                }
            }
        }

        if let startupSectionString = json["startupSection"].string,
           let startupSection = StartupSection(rawValue: startupSectionString)
        {
            Defaults[.startupSection] = startupSection
        }

        if let showSearchSuggestions = json["showSearchSuggestions"].bool {
            Defaults[.showSearchSuggestions] = showSearchSuggestions
        }

        if let visibleSections = json["visibleSections"].array {
            let sections = visibleSections.compactMap { visibleSectionJSON in
                if let visibleSectionString = visibleSectionJSON.rawString(options: []),
                   let section = VisibleSection(rawValue: visibleSectionString)
                {
                    return section
                }
                return nil
            }

            Defaults[.visibleSections] = Set(sections)
        }

        #if os(iOS)
            if let showOpenActionsToolbarItem = json["showOpenActionsToolbarItem"].bool {
                Defaults[.showOpenActionsToolbarItem] = showOpenActionsToolbarItem
            }

            if let lockPortraitWhenBrowsing = json["lockPortraitWhenBrowsing"].bool {
                Defaults[.lockPortraitWhenBrowsing] = lockPortraitWhenBrowsing
            }
        #endif

        #if !os(tvOS)
            if let accountPickerDisplaysUsername = json["accountPickerDisplaysUsername"].bool {
                Defaults[.accountPickerDisplaysUsername] = accountPickerDisplaysUsername
            }
        #endif

        if let accountPickerDisplaysAnonymousAccounts = json["accountPickerDisplaysAnonymousAccounts"].bool {
            Defaults[.accountPickerDisplaysAnonymousAccounts] = accountPickerDisplaysAnonymousAccounts
        }

        if let showUnwatchedFeedBadges = json["showUnwatchedFeedBadges"].bool {
            Defaults[.showUnwatchedFeedBadges] = showUnwatchedFeedBadges
        }

        if let expandChannelDescription = json["expandChannelDescription"].bool {
            Defaults[.expandChannelDescription] = expandChannelDescription
        }

        if let keepChannelsWithUnwatchedFeedOnTop = json["keepChannelsWithUnwatchedFeedOnTop"].bool {
            Defaults[.keepChannelsWithUnwatchedFeedOnTop] = keepChannelsWithUnwatchedFeedOnTop
        }

        if let showChannelAvatarInChannelsLists = json["showChannelAvatarInChannelsLists"].bool {
            Defaults[.showChannelAvatarInChannelsLists] = showChannelAvatarInChannelsLists
        }

        if let showChannelAvatarInVideosListing = json["showChannelAvatarInVideosListing"].bool {
            Defaults[.showChannelAvatarInVideosListing] = showChannelAvatarInVideosListing
        }

        if let playerButtonSingleTapGestureString = json["playerButtonSingleTapGesture"].string,
           let playerButtonSingleTapGesture = PlayerTapGestureAction(rawValue: playerButtonSingleTapGestureString)
        {
            Defaults[.playerButtonSingleTapGesture] = playerButtonSingleTapGesture
        }

        if let playerButtonDoubleTapGestureString = json["playerButtonDoubleTapGesture"].string,
           let playerButtonDoubleTapGesture = PlayerTapGestureAction(rawValue: playerButtonDoubleTapGestureString)
        {
            Defaults[.playerButtonDoubleTapGesture] = playerButtonDoubleTapGesture
        }

        if let playerButtonShowsControlButtonsWhenMinimized = json["playerButtonShowsControlButtonsWhenMinimized"].bool {
            Defaults[.playerButtonShowsControlButtonsWhenMinimized] = playerButtonShowsControlButtonsWhenMinimized
        }

        if let playerButtonIsExpanded = json["playerButtonIsExpanded"].bool {
            Defaults[.playerButtonIsExpanded] = playerButtonIsExpanded
        }

        if let playerBarMaxWidth = json["playerBarMaxWidth"].string {
            Defaults[.playerBarMaxWidth] = playerBarMaxWidth
        }

        if let channelOnThumbnail = json["channelOnThumbnail"].bool {
            Defaults[.channelOnThumbnail] = channelOnThumbnail
        }

        if let timeOnThumbnail = json["timeOnThumbnail"].bool {
            Defaults[.timeOnThumbnail] = timeOnThumbnail
        }

        if let roundedThumbnails = json["roundedThumbnails"].bool {
            Defaults[.roundedThumbnails] = roundedThumbnails
        }

        if let thumbnailsQualityString = json["thumbnailsQuality"].string,
           let thumbnailsQuality = ThumbnailsQuality(rawValue: thumbnailsQualityString)
        {
            Defaults[.thumbnailsQuality] = thumbnailsQuality
        }
    }
}
