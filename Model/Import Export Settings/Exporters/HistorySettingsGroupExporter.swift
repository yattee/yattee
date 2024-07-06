import Defaults
import SwiftyJSON

final class HistorySettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "saveRecents": Defaults[.saveRecents],
            "saveHistory": Defaults[.saveHistory],
            "showRecents": Defaults[.showRecents],
            "limitRecents": Defaults[.limitRecents],
            "limitRecentsAmount": Defaults[.limitRecentsAmount],
            "showWatchingProgress": Defaults[.showWatchingProgress],
            "saveLastPlayed": Defaults[.saveLastPlayed],

            "watchedVideoPlayNowBehavior": Defaults[.watchedVideoPlayNowBehavior].rawValue,
            "watchedThreshold": Defaults[.watchedThreshold],
            "resetWatchedStatusOnPlaying": Defaults[.resetWatchedStatusOnPlaying],

            "watchedVideoStyle": Defaults[.watchedVideoStyle].rawValue,
            "watchedVideoBadgeColor": Defaults[.watchedVideoBadgeColor].rawValue,
            "showToggleWatchedStatusButton": Defaults[.showToggleWatchedStatusButton]
        ]
    }
}
