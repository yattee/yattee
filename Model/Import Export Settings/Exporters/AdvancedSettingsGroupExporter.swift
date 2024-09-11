import Defaults
import SwiftyJSON

final class AdvancedSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "showPlayNowInBackendContextMenu": Defaults[.showPlayNowInBackendContextMenu],
            "videoLoadingRetryCount": Defaults[.videoLoadingRetryCount],
            "showMPVPlaybackStats": Defaults[.showMPVPlaybackStats],
            "mpvEnableLogging": Defaults[.mpvEnableLogging],
            "mpvCacheSecs": Defaults[.mpvCacheSecs],
            "mpvCachePauseWait": Defaults[.mpvCachePauseWait],
            "mpvCachePauseInital": Defaults[.mpvCachePauseInital],
            "mpvDeinterlace": Defaults[.mpvDeinterlace],
            "mpvHWdec": Defaults[.mpvHWdec],
            "mpvDemuxerLavfProbeInfo": Defaults[.mpvDemuxerLavfProbeInfo],
            "mpvSetRefreshToContentFPS": Defaults[.mpvSetRefreshToContentFPS],
            "mpvInitialAudioSync": Defaults[.mpvInitialAudioSync],
            "showCacheStatus": Defaults[.showCacheStatus],
            "feedCacheSize": Defaults[.feedCacheSize]
        ]
    }
}
