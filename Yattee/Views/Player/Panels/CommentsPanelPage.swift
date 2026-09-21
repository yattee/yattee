//
//  CommentsPanelPage.swift
//  Yattee
//
//  Details panel page with the inline comments list.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct CommentsPanelPage: View {
    let context: PanelPageContext
    var scrollConfig: PanelScrollConfig = PanelScrollConfig()

    private var appEnvironment: AppEnvironment? { context.appEnvironment }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }

    var body: some View {
        PanelPageScrollView(config: scrollConfig) {
            CommentsListContent(videoID: context.video.id.videoID)
                .padding(.horizontal)
        }
        .task(id: context.video.id) {
            // Opening the page is an explicit request; load even when the
            // buffer-ready preload hasn't fired yet.
            guard let playerState,
                  playerState.commentsState == .idle,
                  let contentService = appEnvironment?.contentService,
                  let instancesManager = appEnvironment?.instancesManager else { return }
            await playerState.loadComments(contentService: contentService, instancesManager: instancesManager)
        }
    }
}

#endif
