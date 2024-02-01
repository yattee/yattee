import Defaults
import SwiftyJSON

struct PlayerSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let playerInstanceID = json["playerInstanceID"].string {
            Defaults[.playerInstanceID] = playerInstanceID
        }

        if let pauseOnHidingPlayer = json["pauseOnHidingPlayer"].bool {
            Defaults[.pauseOnHidingPlayer] = pauseOnHidingPlayer
        }

        if let closeVideoOnEOF = json["closeVideoOnEOF"].bool {
            Defaults[.closeVideoOnEOF] = closeVideoOnEOF
        }

        if let expandVideoDescription = json["expandVideoDescription"].bool {
            Defaults[.expandVideoDescription] = expandVideoDescription
        }

        if let collapsedLinesDescription = json["collapsedLinesDescription"].int {
            Defaults[.collapsedLinesDescription] = collapsedLinesDescription
        }

        if let showChapters = json["showChapters"].bool {
            Defaults[.showChapters] = showChapters
        }

        if let expandChapters = json["expandChapters"].bool {
            Defaults[.expandChapters] = expandChapters
        }

        if let showRelated = json["showRelated"].bool {
            Defaults[.showRelated] = showRelated
        }

        if let showInspectorString = json["showInspector"].string,
           let showInspector = ShowInspectorSetting(rawValue: showInspectorString)
        {
            Defaults[.showInspector] = showInspector
        }

        if let playerSidebarString = json["playerSidebar"].string,
           let playerSidebar = PlayerSidebarSetting(rawValue: playerSidebarString)
        {
            Defaults[.playerSidebar] = playerSidebar
        }

        if let showKeywords = json["showKeywords"].bool {
            Defaults[.showKeywords] = showKeywords
        }

        if let enableReturnYouTubeDislike = json["enableReturnYouTubeDislike"].bool {
            Defaults[.enableReturnYouTubeDislike] = enableReturnYouTubeDislike
        }

        if let closePiPOnNavigation = json["closePiPOnNavigation"].bool {
            Defaults[.closePiPOnNavigation] = closePiPOnNavigation
        }

        if let closePiPOnOpeningPlayer = json["closePiPOnOpeningPlayer"].bool {
            Defaults[.closePiPOnOpeningPlayer] = closePiPOnOpeningPlayer
        }

        if let closePlayerOnOpeningPiP = json["closePlayerOnOpeningPiP"].bool {
            Defaults[.closePlayerOnOpeningPiP] = closePlayerOnOpeningPiP
        }

        #if !os(macOS)
            if let pauseOnEnteringBackground = json["pauseOnEnteringBackground"].bool {
                Defaults[.pauseOnEnteringBackground] = pauseOnEnteringBackground
            }
        #endif

        #if !os(tvOS)
            if let showScrollToTopInComments = json["showScrollToTopInComments"].bool {
                Defaults[.showScrollToTopInComments] = showScrollToTopInComments
            }
        #endif

        #if os(iOS)
            if let honorSystemOrientationLock = json["honorSystemOrientationLock"].bool {
                Defaults[.honorSystemOrientationLock] = honorSystemOrientationLock
            }

            if let enterFullscreenInLandscape = json["enterFullscreenInLandscape"].bool {
                Defaults[.enterFullscreenInLandscape] = enterFullscreenInLandscape
            }

            if let rotateToLandscapeOnEnterFullScreenString = json["rotateToLandscapeOnEnterFullScreen"].string,
               let rotateToLandscapeOnEnterFullScreen = FullScreenRotationSetting(rawValue: rotateToLandscapeOnEnterFullScreenString)
            {
                Defaults[.rotateToLandscapeOnEnterFullScreen] = rotateToLandscapeOnEnterFullScreen
            }
        #endif
    }
}
