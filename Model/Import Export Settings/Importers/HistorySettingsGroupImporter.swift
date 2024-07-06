import Defaults
import SwiftyJSON

struct HistorySettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let saveRecents = json["saveRecents"].bool {
            Defaults[.saveRecents] = saveRecents
        }

        if let saveHistory = json["saveHistory"].bool {
            Defaults[.saveHistory] = saveHistory
        }

        if let showRecents = json["showRecents"].bool {
            Defaults[.showRecents] = showRecents
        }

        if let limitRecents = json["limitRecents"].bool {
            Defaults[.limitRecents] = limitRecents
        }

        if let limitRecentsAmount = json["limitRecentsAmount"].int {
            Defaults[.limitRecentsAmount] = limitRecentsAmount
        }

        if let showWatchingProgress = json["showWatchingProgress"].bool {
            Defaults[.showWatchingProgress] = showWatchingProgress
        }

        if let saveLastPlayed = json["saveLastPlayed"].bool {
            Defaults[.saveLastPlayed] = saveLastPlayed
        }

        if let watchedVideoPlayNowBehaviorString = json["watchedVideoPlayNowBehavior"].string,
           let watchedVideoPlayNowBehavior = WatchedVideoPlayNowBehavior(rawValue: watchedVideoPlayNowBehaviorString)
        {
            Defaults[.watchedVideoPlayNowBehavior] = watchedVideoPlayNowBehavior
        }

        if let watchedThreshold = json["watchedThreshold"].int {
            Defaults[.watchedThreshold] = watchedThreshold
        }

        if let resetWatchedStatusOnPlaying = json["resetWatchedStatusOnPlaying"].bool {
            Defaults[.resetWatchedStatusOnPlaying] = resetWatchedStatusOnPlaying
        }

        if let watchedVideoStyleString = json["watchedVideoStyle"].string,
           let watchedVideoStyle = WatchedVideoStyle(rawValue: watchedVideoStyleString)
        {
            Defaults[.watchedVideoStyle] = watchedVideoStyle
        }

        if let watchedVideoBadgeColorString = json["watchedVideoBadgeColor"].string,
           let watchedVideoBadgeColor = WatchedVideoBadgeColor(rawValue: watchedVideoBadgeColorString)
        {
            Defaults[.watchedVideoBadgeColor] = watchedVideoBadgeColor
        }

        if let showToggleWatchedStatusButton = json["showToggleWatchedStatusButton"].bool {
            Defaults[.showToggleWatchedStatusButton] = showToggleWatchedStatusButton
        }
    }
}
