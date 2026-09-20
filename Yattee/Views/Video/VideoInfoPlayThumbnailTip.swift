//
//  VideoInfoPlayThumbnailTip.swift
//  Yattee
//
//  TipKit hint that the hero thumbnail plays the video. Shown once, only while the
//  toolbar action layout is active (the inline layout has an explicit Play button).
//

#if !os(tvOS)
import SwiftUI
import TipKit

struct VideoInfoPlayThumbnailTip: Tip {
    /// Mirrors `SettingsManager.videoInfoActionsLayout == .toolbar`; updated by VideoInfoView.
    @Parameter
    static var isToolbarLayout: Bool = false

    var title: Text {
        Text(String(localized: "videoInfo.playTip.title"))
    }

    var message: Text? {
        Text(String(localized: "videoInfo.playTip.message"))
    }

    var image: Image? {
        Image(systemName: "play.circle")
    }

    var rules: [Rule] {
        #Rule(Self.$isToolbarLayout) { $0 == true }
    }
}

/// Attaches the play-thumbnail tip to the hero thumbnail when enabled.
struct VideoInfoPlayThumbnailTipModifier: ViewModifier {
    let enabled: Bool
    private let tip = VideoInfoPlayThumbnailTip()

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func body(content: Content) -> some View {
        if enabled {
            content.popoverTip(tip, arrowEdge: .top)
        } else {
            content
        }
    }
}
#endif
