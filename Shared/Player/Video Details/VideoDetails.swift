import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoDetails: View {
    enum DetailsPage: String, CaseIterable, Defaults.Serializable {
        case info, inspector, chapters, comments, related, queue
    }

    @Binding var page: DetailsPage
    @Binding var sidebarQueue: Bool
    @Binding var fullScreen: Bool
    var bottomPadding = false

    @State private var subscribed = false
    @State private var subscriptionToggleButtonDisabled = false

    @Environment(\.navigationStyle) private var navigationStyle
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var accounts = AccountsModel.shared
    let comments = CommentsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike
    @Default(.detailsToolbarPosition) private var detailsToolbarPosition
    @Default(.playerSidebar) private var playerSidebar

    var video: Video? {
        player.currentVideo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlsBar(
                fullScreen: $fullScreen,
                presentingControls: false,
                backgroundEnabled: false,
                borderTop: false,
                detailsTogglePlayer: false,
                detailsToggleFullScreen: true
            )

            VideoActions(video: video)

            ZStack(alignment: .bottom) {
                currentPage
                    .frame(maxWidth: detailsSize.width)
                    .transition(.fade)

                HStack {
                    if detailsToolbarPosition.needsLeftSpacer { Spacer() }

                    VideoDetailsToolbar(video: video, page: $page, sidebarQueue: sidebarQueue)

                    if detailsToolbarPosition.needsRightSpacer { Spacer() }
                }
                .padding(.leading, detailsToolbarPosition == .left ? 10 : 0)
                .padding(.trailing, detailsToolbarPosition == .right ? 10 : 0)

                #if os(iOS)
                    .offset(y: bottomPadding ? -SafeArea.insets.bottom : 0)
                #endif
            }
            .onChange(of: player.currentItem) { newItem in
                Delay.by(0.2) {
                    guard let newItem else {
                        page = sidebarQueue ? .inspector : .queue
                        return
                    }

                    if let video = newItem.video {
                        page = video.isLocal ? .inspector : .info
                    } else {
                        page = sidebarQueue ? .inspector : .queue
                    }
                }
            }
        }
        .onAppear {
            if video.isNil ||
                !VideoDetailsTool.find(for: page)!.isAvailable(for: video!, sidebarQueue: sidebarQueue)
            {
                page = video == nil ? (sidebarQueue ? .inspector : .queue) : (video!.isLocal ? .inspector : .info)
            }

            guard video != nil, accounts.app.supportsSubscriptions else {
                subscribed = false
                return
            }
        }
        .onChange(of: sidebarQueue) { queue in
            if queue {
                if page == .related || page == .queue {
                    page = video.isNil || video!.isLocal ? .inspector : .info
                }
            } else if video.isNil {
                page = .inspector
            }
        }
        .overlay(GeometryReader { proxy in
            Color.clear
                .onAppear {
                    detailsSize = proxy.size
                }
                .onChange(of: proxy.size) { newSize in
                    detailsSize = newSize
                }
        })
        .background(colorScheme == .dark ? Color.black : .white)
    }

    private var contentItem: ContentItem {
        ContentItem(video: player.currentVideo)
    }

    var currentPage: some View {
        VStack {
            switch page {
            case .info:
                detailsPage

            case .inspector:
                InspectorView(video: video)

            case .chapters:
                ChaptersView()

            case .comments:
                CommentsView(embedInScrollView: true)
                    .onAppear {
                        Delay.by(0.3) { comments.loadIfNeeded() }
                    }

            case .related:
                RelatedView()

            case .queue:
                PlayerQueueView(sidebarQueue: sidebarQueue, fullScreen: $fullScreen)
            }
        }
        .contentShape(Rectangle())
        .frame(maxHeight: .infinity)
    }

    @State private var detailsSize = CGSize.zero

    var detailsPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let video {
                VStack(alignment: .leading, spacing: 10) {
                    videoProperties

                    if !player.videoBeingOpened.isNil && (video.description.isNil || video.description!.isEmpty) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(1 ... Int.random(in: 2 ... 5), id: \.self) { _ in
                                Text(String(repeating: Video.fixture.description ?? "", count: Int.random(in: 1 ... 4)))
                            }
                        }
                        .redacted(reason: .placeholder)
                    } else if video.description != nil, !video.description!.isEmpty {
                        VideoDescription(video: video, detailsSize: detailsSize)
                        #if os(iOS)
                            .padding(.bottom, player.playingFullScreen ? 10 : SafeArea.insets.bottom)
                        #endif
                    } else if !video.isLocal {
                        Text("No description")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 60)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder var videoProperties: some View {
        HStack(spacing: 2) {
            publishedDateSection

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "eye")

                if let views = video?.viewsCount, player.videoBeingOpened.isNil {
                    Text(views)
                } else {
                    if player.videoBeingOpened == nil {
                        Text("?")
                    } else {
                        Text("1,234M").redacted(reason: .placeholder)
                    }
                }

                Image(systemName: "hand.thumbsup")

                if let likes = video?.likesCount, player.videoBeingOpened.isNil {
                    Text(likes)
                } else {
                    if player.videoBeingOpened == nil {
                        Text("?")
                    } else {
                        Text("1,234M").redacted(reason: .placeholder)
                    }
                }

                if enableReturnYouTubeDislike {
                    Image(systemName: "hand.thumbsdown")

                    if let dislikes = video?.dislikesCount, player.videoBeingOpened.isNil {
                        Text(dislikes)
                    } else {
                        if player.videoBeingOpened == nil {
                            Text("?")
                        } else {
                            Text("1,234M").redacted(reason: .placeholder)
                        }
                    }
                }
            }
        }
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }

    var publishedDateSection: some View {
        Group {
            if let video {
                HStack(spacing: 4) {
                    if let published = video.publishedDate {
                        Text(published)
                    } else {
                        Text("1 century ago").redacted(reason: .placeholder)
                    }
                }
            }
        }
    }
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(page: .constant(.info), sidebarQueue: .constant(true), fullScreen: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
