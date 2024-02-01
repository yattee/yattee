import Defaults
import SwiftyJSON

struct AdvancedSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let showPlayNowInBackendContextMenu = json["showPlayNowInBackendContextMenu"].bool {
            Defaults[.showPlayNowInBackendContextMenu] = showPlayNowInBackendContextMenu
        }

        if let showMPVPlaybackStats = json["showMPVPlaybackStats"].bool {
            Defaults[.showMPVPlaybackStats] = showMPVPlaybackStats
        }

        if let mpvEnableLogging = json["mpvEnableLogging"].bool {
            Defaults[.mpvEnableLogging] = mpvEnableLogging
        }

        if let mpvCacheSecs = json["mpvCacheSecs"].string {
            Defaults[.mpvCacheSecs] = mpvCacheSecs
        }

        if let mpvCachePauseWait = json["mpvCachePauseWait"].string {
            Defaults[.mpvCachePauseWait] = mpvCachePauseWait
        }

        if let showCacheStatus = json["showCacheStatus"].bool {
            Defaults[.showCacheStatus] = showCacheStatus
        }

        if let feedCacheSize = json["feedCacheSize"].string {
            Defaults[.feedCacheSize] = feedCacheSize
        }
    }
}
