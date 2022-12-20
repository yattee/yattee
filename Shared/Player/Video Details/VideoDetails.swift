import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoDetails: View {
    enum DetailsPage: String, CaseIterable, Defaults.Serializable {
        case info, comments, chapters, inspector

        var systemImageName: String {
            switch self {
            case .info:
                return "info.circle"
            case .inspector:
                return "wand.and.stars"
            case .comments:
                return "text.bubble"
            case .chapters:
                return "bookmark"
            }
        }

        var title: String {
            rawValue.capitalized.localized()
        }
    }

    var video: Video?

    @Binding var fullScreen: Bool
    var bottomPadding = false

    @State private var detailsSize = CGSize.zero
    @State private var descriptionVisibility = Constants.descriptionVisibility
    @State private var subscribed = false
    @State private var subscriptionToggleButtonDisabled = false
    @State private var page = DetailsPage.info

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

            pageView
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

    @ViewBuilder var pageMenu: some View {
        #if os(macOS)
            pagePicker
                .labelsHidden()
                .offset(x: 15, y: 15)
                .frame(maxWidth: 200)
        #elseif os(iOS)
            Menu {
                pagePicker
            } label: {
                HStack {
                    Label(page.title, systemImage: page.systemImageName)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .padding(10)
                .fixedSize(horizontal: true, vertical: false)
                .modifier(ControlBackgroundModifier())
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 200, alignment: .leading)
                .transaction { t in t.animation = nil }
            }
            .animation(nil, value: descriptionVisibility)
            .modifier(SettingsPickerModifier())
            .offset(x: 15, y: 5)
            .opacity(descriptionVisibility ? 1 : 0)
        #endif
    }

    var pagePicker: some View {
        Picker("Page", selection: $page) {
            ForEach(DetailsPage.allCases, id: \.rawValue) { page in
                Label(page.title, systemImage: page.systemImageName).tag(page)
            }
        }
    }

    var pageView: some View {
        ZStack(alignment: .topLeading) {
            switch page {
            case .info:
                ScrollView(.vertical, showsIndicators: false) {
                    if let video {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                videoProperties
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                #if os(iOS)
                                    .opacity(descriptionVisibility ? 1 : 0)
                                #endif
                            }
                            .padding(.bottom, 12)

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
                        .padding(.top, 18)
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
                #if os(iOS)
                    .frame(maxWidth: YatteeApp.isForPreviews ? .infinity : maxWidth)
                #endif

            case .inspector:
                InspectorView(video: video)

            case .chapters:
                ChaptersView()

            case .comments:
                CommentsView(embedInScrollView: true)
                    .onAppear {
                        comments.loadIfNeeded()
                    }
            }

            pageMenu
                .font(.headline)
                .foregroundColor(.accentColor)
                .zIndex(1)

            #if !os(tvOS)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: .init(colors: [fadePlaceholderStartColor, .clear]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .zIndex(0)
                    .frame(maxHeight: 25)
            #endif
        }
    }

    var fadePlaceholderStartColor: Color {
        #if os(macOS)
            .secondaryBackground
        #elseif os(iOS)
            .background
        #else
            .clear
        #endif
    }

    @ViewBuilder var videoProperties: some View {
        HStack(spacing: 4) {
            Spacer()
            publishedDateSection

            Text("•")

            HStack(spacing: 4) {
                if player.videoBeingOpened != nil || video?.viewsCount != nil {
                    Image(systemName: "eye")
                }

                if let views = video?.viewsCount {
                    Text(views)
                } else if player.videoBeingOpened != nil {
                    Text("1,234M").redacted(reason: .placeholder)
                }

                if player.videoBeingOpened != nil || video?.likesCount != nil {
                    Image(systemName: "hand.thumbsup")
                }

                if let likes = video?.likesCount {
                    Text(likes)
                } else if player.videoBeingOpened == nil {
                    Text("1,234M").redacted(reason: .placeholder)
                }

                if enableReturnYouTubeDislike {
                    if player.videoBeingOpened != nil || video?.dislikesCount != nil {
                        Image(systemName: "hand.thumbsdown")
                    }

                    if let dislikes = video?.dislikesCount {
                        Text(dislikes)
                    } else if player.videoBeingOpened == nil {
                        Text("1,234M").redacted(reason: .placeholder)
                    }
                }
            }
        }
        .font(.caption)
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
