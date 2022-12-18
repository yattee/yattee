import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoDetails: View {
    enum DetailsPage: String, CaseIterable, Defaults.Serializable {
        case info, inspector, chapters, comments, related, queue
    }

    var video: Video?

    @Binding var fullScreen: Bool
    var bottomPadding = false

    @State private var detailsSize = CGSize.zero
    @State private var descriptionVisibility = Constants.descriptionVisibility
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
    @Default(.playerSidebar) private var playerSidebar

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ControlsBar(
                fullScreen: $fullScreen,
                expansionState: .constant(.full),
                presentingControls: false,
                backgroundEnabled: false,
                borderTop: false,
                detailsTogglePlayer: false,
                detailsToggleFullScreen: true
            )
            .animation(nil, value: player.currentItem)

            VideoActions(video: player.videoForDisplay)
                .animation(nil, value: player.currentItem)

            detailsPage
            #if os(iOS)
            .frame(maxWidth: maxWidth)
            #endif
        }
        .overlay(GeometryReader { proxy in
            Color.clear
                .onAppear {
                    detailsSize = proxy.size
                }
                .onChange(of: proxy.size) { newSize in
                    guard !player.playingFullScreen else { return }
                    detailsSize = newSize
                }
        })
        .background(colorScheme == .dark ? Color.black : .white)
    }

    #if os(iOS)
        private var maxWidth: Double {
            let width = min(detailsSize.width, player.playerSize.width)
            if width.isNormal, width > 0 {
                return width
            }

            return 0
        }
    #endif

    private var contentItem: ContentItem {
        ContentItem(video: player.currentVideo)
    }

    var detailsPage: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let video {
                VStack(alignment: .leading, spacing: 10) {
                    videoProperties
                    #if os(iOS)
                    .opacity(descriptionVisibility ? 1 : 0)
                    #endif

                    if !player.videoBeingOpened.isNil && (video.description.isNil || video.description!.isEmpty) {
                        VStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                        }
                        .frame(maxWidth: .infinity)
                        .opacity(descriptionVisibility ? 1 : 0)
                    } else if video.description != nil, !video.description!.isEmpty {
                        VideoDescription(video: video, detailsSize: detailsSize)
                        #if os(iOS)
                            .opacity(descriptionVisibility ? 1 : 0)
                            .padding(.bottom, player.playingFullScreen ? 10 : SafeArea.insets.bottom)
                        #endif
                    } else if !video.isLocal {
                        Text("No description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 60)
            }
        }
        #if os(iOS)
        .onAppear {
            if fullScreen {
                descriptionVisibility = true
                return
            }
            Delay.by(0.4) { withAnimation(.easeIn(duration: 0.25)) { self.descriptionVisibility = true } }
        }
        #endif
        .transition(.opacity)
        .animation(nil, value: player.currentItem)
        .padding(.horizontal)
    }

    @ViewBuilder var videoProperties: some View {
        HStack(spacing: 2) {
            publishedDateSection

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "eye")

                if let views = video?.viewsCount {
                    Text(views)
                } else {
                    if player.videoBeingOpened == nil {
                        Text("?")
                    } else {
                        Text("1,234M").redacted(reason: .placeholder)
                    }
                }

                Image(systemName: "hand.thumbsup")

                if let likes = video?.likesCount {
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

                    if let dislikes = video?.dislikesCount {
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
        VideoDetails(video: .fixture, fullScreen: .constant(false))
    }
}
