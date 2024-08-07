import Defaults
import SwiftyJSON

final class AdvancedSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "showPlayNowInBackendContextMenu": Defaults[.showPlayNowInBackendContextMenu],
            "showMPVPlaybackStats": Defaults[.showMPVPlaybackStats],
            "mpvEnableLogging": Defaults[.mpvEnableLogging],
            "mpvCacheSecs": Defaults[.mpvCacheSecs],
            "mpvCachePauseWait": Defaults[.mpvCachePauseWait],
            "mpvCachePauseInital": Defaults[.mpvCachePauseInital],
            "mpvDeinterlace": Defaults[.mpvDeinterlace],
            "mpvHWdec": Defaults[.mpvHWdec],
            "mpvDemuxerLavfProbeInfo": Defaults[.mpvDemuxerLavfProbeInfo],
            "mpvInitialAudioSync": Defaults[.mpvInitialAudioSync],
            "showCacheStatus": Defaults[.showCacheStatus],
            "feedCacheSize": Defaults[.feedCacheSize]
        ]
    }
}
