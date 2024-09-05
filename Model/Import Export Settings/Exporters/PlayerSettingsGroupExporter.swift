import Defaults
import SwiftyJSON

final class PlayerSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "playerInstanceID": Defaults[.playerInstanceID] ?? "",
            "pauseOnHidingPlayer": Defaults[.pauseOnHidingPlayer],
            "closeVideoOnEOF": Defaults[.closeVideoOnEOF],
            "exitFullscreenOnEOF": Defaults[.exitFullscreenOnEOF],
            "expandVideoDescription": Defaults[.expandVideoDescription],
            "collapsedLinesDescription": Defaults[.collapsedLinesDescription],
            "showChapters": Defaults[.showChapters],
            "showChapterThumbnails": Defaults[.showChapterThumbnails],
            "showChapterThumbnailsOnlyWhenDifferent": Defaults[.showChapterThumbnailsOnlyWhenDifferent],
            "expandChapters": Defaults[.expandChapters],
            "showRelated": Defaults[.showRelated],
            "showInspector": Defaults[.showInspector].rawValue,
            "playerSidebar": Defaults[.playerSidebar].rawValue,
            "showKeywords": Defaults[.showKeywords],
            "enableReturnYouTubeDislike": Defaults[.enableReturnYouTubeDislike],
            "closePiPOnNavigation": Defaults[.closePiPOnNavigation],
            "closePiPOnOpeningPlayer": Defaults[.closePiPOnOpeningPlayer],
            "closePlayerOnOpeningPiP": Defaults[.closePlayerOnOpeningPiP],
            "captionsAutoShow": Defaults[.captionsAutoShow],
            "captionsDefaultLanguageCode": Defaults[.captionsDefaultLanguageCode],
            "captionsFallbackLanguageCode": Defaults[.captionsFallbackLanguageCode],
            "captionsFontScaleSize": Defaults[.captionsFontScaleSize],
            "captionsFontColor": Defaults[.captionsFontColor]
        ]
    }

    override var platformJSON: JSON {
        var export = JSON()

        #if !os(macOS)
            export["pauseOnEnteringBackground"].bool = Defaults[.pauseOnEnteringBackground]
        #endif

        export["showComments"].bool = Defaults[.showComments]

        #if !os(tvOS)
            export["showScrollToTopInComments"].bool = Defaults[.showScrollToTopInComments]
        #endif

        #if os(iOS)
            export["isOrientationLocked"].bool = Defaults[.isOrientationLocked]
            export["enterFullscreenInLandscape"].bool = Defaults[.enterFullscreenInLandscape]
            export["rotateToLandscapeOnEnterFullScreen"].string = Defaults[.rotateToLandscapeOnEnterFullScreen].rawValue
        #endif

        return export
    }
}
