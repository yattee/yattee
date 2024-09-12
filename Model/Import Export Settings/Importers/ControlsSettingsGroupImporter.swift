import Defaults
import SwiftyJSON

struct ConstrolsSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let avPlayerUsesSystemControls = json["avPlayerUsesSystemControls"].bool {
            Defaults[.avPlayerUsesSystemControls] = avPlayerUsesSystemControls
        }

        if let fullscreenPlayerGestureEnabled = json["fullscreenPlayerGestureEnabled"].bool {
            Defaults[.fullscreenPlayerGestureEnabled] = fullscreenPlayerGestureEnabled
        }

        if let horizontalPlayerGestureEnabled = json["horizontalPlayerGestureEnabled"].bool {
            Defaults[.horizontalPlayerGestureEnabled] = horizontalPlayerGestureEnabled
        }

        if let seekGestureSensitivity = json["seekGestureSensitivity"].double {
            Defaults[.seekGestureSensitivity] = seekGestureSensitivity
        }

        if let seekGestureSpeed = json["seekGestureSpeed"].double {
            Defaults[.seekGestureSpeed] = seekGestureSpeed
        }

        if let playerControlsLayoutString = json["playerControlsLayout"].string,
           let playerControlsLayout = PlayerControlsLayout(rawValue: playerControlsLayoutString)
        {
            Defaults[.playerControlsLayout] = playerControlsLayout
        }

        if let fullScreenPlayerControlsLayoutString = json["fullScreenPlayerControlsLayout"].string,
           let fullScreenPlayerControlsLayout = PlayerControlsLayout(rawValue: fullScreenPlayerControlsLayoutString)
        {
            Defaults[.fullScreenPlayerControlsLayout] = fullScreenPlayerControlsLayout
        }

        if let playerControlsBackgroundOpacity = json["playerControlsBackgroundOpacity"].double {
            Defaults[.playerControlsBackgroundOpacity] = playerControlsBackgroundOpacity
        }

        if let systemControlsCommandsString = json["systemControlsCommands"].string,
           let systemControlsCommands = SystemControlsCommands(rawValue: systemControlsCommandsString)
        {
            Defaults[.systemControlsCommands] = systemControlsCommands
        }

        if let buttonBackwardSeekDuration = json["buttonBackwardSeekDuration"].string {
            Defaults[.buttonBackwardSeekDuration] = buttonBackwardSeekDuration
        }

        if let buttonForwardSeekDuration = json["buttonForwardSeekDuration"].string {
            Defaults[.buttonForwardSeekDuration] = buttonForwardSeekDuration
        }

        if let gestureBackwardSeekDuration = json["gestureBackwardSeekDuration"].string {
            Defaults[.gestureBackwardSeekDuration] = gestureBackwardSeekDuration
        }

        if let gestureForwardSeekDuration = json["gestureForwardSeekDuration"].string {
            Defaults[.gestureForwardSeekDuration] = gestureForwardSeekDuration
        }

        if let systemControlsSeekDuration = json["systemControlsSeekDuration"].string {
            Defaults[.systemControlsSeekDuration] = systemControlsSeekDuration
        }

        if let playerControlsSettingsEnabled = json["playerControlsSettingsEnabled"].bool {
            Defaults[.playerControlsSettingsEnabled] = playerControlsSettingsEnabled
        }

        if let playerControlsCloseEnabled = json["playerControlsCloseEnabled"].bool {
            Defaults[.playerControlsCloseEnabled] = playerControlsCloseEnabled
        }

        if let playerControlsRestartEnabled = json["playerControlsRestartEnabled"].bool {
            Defaults[.playerControlsRestartEnabled] = playerControlsRestartEnabled
        }

        if let playerControlsAdvanceToNextEnabled = json["playerControlsAdvanceToNextEnabled"].bool {
            Defaults[.playerControlsAdvanceToNextEnabled] = playerControlsAdvanceToNextEnabled
        }

        if let playerControlsPlaybackModeEnabled = json["playerControlsPlaybackModeEnabled"].bool {
            Defaults[.playerControlsPlaybackModeEnabled] = playerControlsPlaybackModeEnabled
        }

        if let playerControlsMusicModeEnabled = json["playerControlsMusicModeEnabled"].bool {
            Defaults[.playerControlsMusicModeEnabled] = playerControlsMusicModeEnabled
        }

        if let playerActionsButtonLabelStyleString = json["playerActionsButtonLabelStyle"].string,
           let playerActionsButtonLabelStyle = ButtonLabelStyle(rawValue: playerActionsButtonLabelStyleString)
        {
            Defaults[.playerActionsButtonLabelStyle] = playerActionsButtonLabelStyle
        }

        if let actionButtonShareEnabled = json["actionButtonShareEnabled"].bool {
            Defaults[.actionButtonShareEnabled] = actionButtonShareEnabled
        }

        if let actionButtonAddToPlaylistEnabled = json["actionButtonAddToPlaylistEnabled"].bool {
            Defaults[.actionButtonAddToPlaylistEnabled] = actionButtonAddToPlaylistEnabled
        }

        if let actionButtonSubscribeEnabled = json["actionButtonSubscribeEnabled"].bool {
            Defaults[.actionButtonSubscribeEnabled] = actionButtonSubscribeEnabled
        }

        if let actionButtonSettingsEnabled = json["actionButtonSettingsEnabled"].bool {
            Defaults[.actionButtonSettingsEnabled] = actionButtonSettingsEnabled
        }

        if let actionButtonHideEnabled = json["actionButtonHideEnabled"].bool {
            Defaults[.actionButtonHideEnabled] = actionButtonHideEnabled
        }

        if let actionButtonCloseEnabled = json["actionButtonCloseEnabled"].bool {
            Defaults[.actionButtonCloseEnabled] = actionButtonCloseEnabled
        }

        if let actionButtonFullScreenEnabled = json["actionButtonFullScreenEnabled"].bool {
            Defaults[.actionButtonFullScreenEnabled] = actionButtonFullScreenEnabled
        }

        if let actionButtonPipEnabled = json["actionButtonPipEnabled"].bool {
            Defaults[.actionButtonPipEnabled] = actionButtonPipEnabled
        }

        if let actionButtonLockOrientationEnabled = json["actionButtonLockOrientationEnabled"].bool {
            Defaults[.actionButtonLockOrientationEnabled] = actionButtonLockOrientationEnabled
        }

        if let actionButtonRestartEnabled = json["actionButtonRestartEnabled"].bool {
            Defaults[.actionButtonRestartEnabled] = actionButtonRestartEnabled
        }

        if let actionButtonAdvanceToNextItemEnabled = json["actionButtonAdvanceToNextItemEnabled"].bool {
            Defaults[.actionButtonAdvanceToNextItemEnabled] = actionButtonAdvanceToNextItemEnabled
        }

        if let actionButtonMusicModeEnabled = json["actionButtonMusicModeEnabled"].bool {
            Defaults[.actionButtonMusicModeEnabled] = actionButtonMusicModeEnabled
        }
    }
}
