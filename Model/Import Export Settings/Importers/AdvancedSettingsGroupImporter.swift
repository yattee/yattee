import Defaults
import SwiftyJSON

struct AdvancedSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let showPlayNowInBackendContextMenu = json["showPlayNowInBackendContextMenu"].bool {
            Defaults[.showPlayNowInBackendContextMenu] = showPlayNowInBackendContextMenu
        }

        if let videoLoadingRetryCount = json["videoLoadingRetryCount"].int {
            Defaults[.videoLoadingRetryCount] = videoLoadingRetryCount
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

        if let mpvCachePauseInital = json["mpvCachePauseInital"].bool {
            Defaults[.mpvCachePauseInital] = mpvCachePauseInital
        }

        if let mpvDeinterlace = json["mpvDeinterlace"].bool {
            Defaults[.mpvDeinterlace] = mpvDeinterlace
        }

        if let mpvHWdec = json["mpvHWdec"].string {
            Defaults[.mpvHWdec] = mpvHWdec
        }

        if let mpvDemuxerLavfProbeInfo = json["mpvDemuxerLavfProbeInfo"].string {
            Defaults[.mpvDemuxerLavfProbeInfo] = mpvDemuxerLavfProbeInfo
        }

        if let mpvSetRefreshToContentFPS = json["mpvSetRefreshToContentFPS"].bool {
            Defaults[.mpvSetRefreshToContentFPS] = mpvSetRefreshToContentFPS
        }

        if let mpvInitialAudioSync = json["mpvInitialAudioSync"].bool {
            Defaults[.mpvInitialAudioSync] = mpvInitialAudioSync
        }

        if let showCacheStatus = json["showCacheStatus"].bool {
            Defaults[.showCacheStatus] = showCacheStatus
        }

        if let feedCacheSize = json["feedCacheSize"].string {
            Defaults[.feedCacheSize] = feedCacheSize
        }
    }
}
