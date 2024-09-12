import Defaults
import SwiftyJSON

final class ConstrolsSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "avPlayerUsesSystemControls": Defaults[.avPlayerUsesSystemControls],
            "fullscreenPlayerGestureEnabled": Defaults[.fullscreenPlayerGestureEnabled],
            "horizontalPlayerGestureEnabled": Defaults[.horizontalPlayerGestureEnabled],
            "seekGestureSensitivity": Defaults[.seekGestureSensitivity],
            "seekGestureSpeed": Defaults[.seekGestureSpeed],
            "playerControlsLayout": Defaults[.playerControlsLayout].rawValue,
            "fullScreenPlayerControlsLayout": Defaults[.fullScreenPlayerControlsLayout].rawValue,
            "playerControlsBackgroundOpacity": Defaults[.playerControlsBackgroundOpacity],
            "systemControlsCommands": Defaults[.systemControlsCommands].rawValue,
            "buttonBackwardSeekDuration": Defaults[.buttonBackwardSeekDuration],
            "buttonForwardSeekDuration": Defaults[.buttonForwardSeekDuration],
            "gestureBackwardSeekDuration": Defaults[.gestureBackwardSeekDuration],
            "gestureForwardSeekDuration": Defaults[.gestureForwardSeekDuration],
            "systemControlsSeekDuration": Defaults[.systemControlsSeekDuration],
            "playerControlsSettingsEnabled": Defaults[.playerControlsSettingsEnabled],
            "playerControlsCloseEnabled": Defaults[.playerControlsCloseEnabled],
            "playerControlsRestartEnabled": Defaults[.playerControlsRestartEnabled],
            "playerControlsAdvanceToNextEnabled": Defaults[.playerControlsAdvanceToNextEnabled],
            "playerControlsPlaybackModeEnabled": Defaults[.playerControlsPlaybackModeEnabled],
            "playerControlsMusicModeEnabled": Defaults[.playerControlsMusicModeEnabled],
            "playerActionsButtonLabelStyle": Defaults[.playerActionsButtonLabelStyle].rawValue,
            "actionButtonShareEnabled": Defaults[.actionButtonShareEnabled],
            "actionButtonAddToPlaylistEnabled": Defaults[.actionButtonAddToPlaylistEnabled],
            "actionButtonSubscribeEnabled": Defaults[.actionButtonSubscribeEnabled],
            "actionButtonSettingsEnabled": Defaults[.actionButtonSettingsEnabled],
            "actionButtonHideEnabled": Defaults[.actionButtonHideEnabled],
            "actionButtonCloseEnabled": Defaults[.actionButtonCloseEnabled],
            "actionButtonFullScreenEnabled": Defaults[.actionButtonFullScreenEnabled],
            "actionButtonPipEnabled": Defaults[.actionButtonPipEnabled],
            "actionButtonLockOrientationEnabled": Defaults[.actionButtonLockOrientationEnabled],
            "actionButtonRestartEnabled": Defaults[.actionButtonRestartEnabled],
            "actionButtonAdvanceToNextItemEnabled": Defaults[.actionButtonAdvanceToNextItemEnabled],
            "actionButtonMusicModeEnabled": Defaults[.actionButtonMusicModeEnabled]
        ]
    }
}
