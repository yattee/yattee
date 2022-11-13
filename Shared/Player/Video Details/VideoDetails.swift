import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoDetails: View {
    enum DetailsPage: String, CaseIterable, Defaults.Serializable {
        case info, inspector, chapters, comments, related, queue
    }

    @Binding var sidebarQueue: Bool
    @Binding var fullScreen: Bool
    var bottomPadding = false

    @State private var subscribed = false
    @State private var subscriptionToggleButtonDisabled = false

    @State private var page = DetailsPage.queue

    @Environment(\.navigationStyle) private var navigationStyle
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Environment(\.colorScheme) private var colorScheme

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Default(.playerDetailsPageButtonLabelStyle) private var playerDetailsPageButtonLabelStyle
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
                    .transition(.fade)

                HStack(alignment: .center) {
                    Spacer()
                    VideoDetailsToolbar(video: video, page: $page, sidebarQueue: sidebarQueue)
                    Spacer()
                }
                #if os(iOS)
                .offset(y: bottomPadding ? -SafeArea.insets.bottom : 0)
                #endif
            }
            .onChange(of: player.currentItem) { newItem in
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
        .onAppear {
            page = sidebarQueue ? .inspector : .queue

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
                        comments.loadIfNeeded()
                    }

            case .related:
                RelatedView()

            case .queue:
                PlayerQueueView(sidebarQueue: sidebarQueue, fullScreen: $fullScreen)
            }
        }
        .contentShape(Rectangle())
    }

    @State private var detailsSize = CGSize.zero

    var detailsPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let video {
                VStack(alignment: .leading, spacing: 10) {
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
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(sidebarQueue: .constant(true), fullScreen: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
