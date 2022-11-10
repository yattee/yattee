import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI
import SwiftUIPager

struct VideoDetails: View {
    enum DetailsPage: String, CaseIterable, Defaults.Serializable {
        case info, chapters, comments, related, queue

        var index: Int {
            switch self {
            case .info:
                return 0
            case .chapters:
                return 1
            case .comments:
                return 2
            case .related:
                return 3
            case .queue:
                return 4
            }
        }
    }

    var sidebarQueue: Bool
    @Binding var fullScreen: Bool

    @State private var subscribed = false
    @State private var subscriptionToggleButtonDisabled = false

    @StateObject private var page: Page = .first()

    @Environment(\.navigationStyle) private var navigationStyle
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    @Default(.playerDetailsPageButtonLabelStyle) private var playerDetailsPageButtonLabelStyle

    var currentPage: DetailsPage {
        DetailsPage.allCases.first { $0.index == page.index } ?? .info
    }

    var video: Video? {
        player.currentVideo
    }

    var body: some View {
        if #available(iOS 15, macOS 12, *) {
            Self._printChanges()
        }

        return VStack(alignment: .leading, spacing: 0) {
            ControlsBar(
                fullScreen: $fullScreen,
                presentingControls: false,
                backgroundEnabled: false,
                borderTop: false,
                detailsTogglePlayer: false,
                detailsToggleFullScreen: true
            )

            HStack(spacing: 4) {
                pageButton(
                    "Info".localized(),
                    "info.circle", .info, !video.isNil
                )
                if let video, !video.isLocal {
                    pageButton(
                        "Chapters".localized(),
                        "bookmark", .chapters, !video.chapters.isEmpty && !video.isLocal
                    )
                    pageButton(
                        "Comments".localized(),
                        "text.bubble", .comments, !video.isLocal
                    ) { comments.load() }
                    pageButton(
                        "Related".localized(),
                        "rectangle.stack.fill", .related, !video.isLocal
                    )
                }
                pageButton(
                    "Queue".localized(),
                    "list.number", .queue, !player.queue.isEmpty
                )
            }
            .onChange(of: player.currentItem) { _ in
                page.update(.moveToFirst)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Pager(page: page, data: DetailsPage.allCases, id: \.self) {
                if !player.currentItem.isNil || page.index == DetailsPage.queue.index {
                    detailsByPage($0)
                    #if os(iOS)
                        .padding(.bottom, SafeArea.insets.bottom)
                    #else
                        .padding(.bottom, 6)
                    #endif
                } else {
                    VStack {}
                }
            }

            .onPageWillChange { pageIndex in
                if pageIndex == DetailsPage.comments.index {
                    comments.load()
                }
            }
            .frame(maxWidth: detailsSize.width)
        }
        .onAppear {
            page.update(.moveToFirst)

            guard video != nil, accounts.app.supportsSubscriptions else {
                subscribed = false
                return
            }
        }
        .onChange(of: sidebarQueue) { queue in
            if queue {
                if currentPage == .related || currentPage == .queue {
                    page.update(.moveToFirst)
                }
            } else if video.isNil {
                page.update(.moveToLast)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .overlay(GeometryReader { proxy in
            Color.clear
                .onAppear {
                    detailsSize = proxy.size
                }
                .onChange(of: proxy.size) { newSize in
                    detailsSize = newSize
                }
        })
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

    private var contentItem: ContentItem {
        ContentItem(video: player.currentVideo)
    }

    func pageButton(
        _ label: String,
        _ symbolName: String,
        _ destination: DetailsPage,
        _ active: Bool = true,
        pageChangeAction: (() -> Void)? = nil
    ) -> some View {
        Button(action: {
            page.update(.new(index: destination.index))
            pageChangeAction?()
        }) {
            HStack {
                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: symbolName)

                    if playerDetailsPageButtonLabelStyle.text && player.playerSize.width > 450 {
                        Text(label)
                    }
                }
                .frame(minHeight: 15)
                .lineLimit(1)
                .padding(.vertical, 4)
                .foregroundColor(currentPage == destination ? .white : (active ? Color.accentColor : .gray))

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .background(currentPage == destination ? (active ? Color.accentColor : .gray) : .clear)
        .buttonStyle(.plain)
        .font(.system(size: 10).bold())
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(active ? Color.accentColor : .gray, lineWidth: 1.2)
                .foregroundColor(.clear)
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder func detailsByPage(_ page: DetailsPage) -> some View {
        Group {
            switch page {
            case .info:
                ScrollView(.vertical, showsIndicators: false) {
                    detailsPage
                }
            case .chapters:
                ChaptersView()

            case .comments:
                CommentsView(embedInScrollView: true)

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
        VStack(alignment: .leading, spacing: 0) {
            if let video {
                if !video.isLocal {
                    VStack(spacing: 6) {
                        videoProperties

                        Divider()
                    }
                    .padding(.bottom, 6)
                }

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

                VStack(spacing: 4) {
                    Group {
                        if player.activeBackend == .mpv, player.mpvBackend.videoFormat != "unknown" {
                            videoDetailGroupHeading("Video")

                            videoDetailRow("Format", value: player.mpvBackend.videoFormat)
                            videoDetailRow("Codec", value: player.mpvBackend.videoCodec)
                            videoDetailRow("Hardware Decoder", value: player.mpvBackend.hwDecoder)
                            videoDetailRow("Driver", value: player.mpvBackend.currentVo)
                            videoDetailRow("Size", value: player.formattedSize)
                            videoDetailRow("FPS", value: player.mpvBackend.formattedOutputFps)
                        } else if player.activeBackend == .appleAVPlayer, let width = player.backend.videoWidth, width > 0 {
                            videoDetailGroupHeading("Video")
                            videoDetailRow("Size", value: player.formattedSize)
                        }
                    }

                    if player.activeBackend == .mpv, player.mpvBackend.audioFormat != "unknown" {
                        Group {
                            videoDetailGroupHeading("Audio")
                            videoDetailRow("Format", value: player.mpvBackend.audioFormat)
                            videoDetailRow("Codec", value: player.mpvBackend.audioCodec)
                            videoDetailRow("Driver", value: player.mpvBackend.currentAo)
                            videoDetailRow("Channels", value: player.mpvBackend.audioChannels)
                            videoDetailRow("Sample Rate", value: player.mpvBackend.audioSampleRate)
                        }
                    }

                    if video.localStream != nil || video.localStreamFileExtension != nil {
                        videoDetailGroupHeading("File")
                    }

                    if let fileExtension = video.localStreamFileExtension {
                        videoDetailRow("File Extension", value: fileExtension)
                    }

                    if let url = video.localStream?.localURL, video.localStreamIsRemoteURL {
                        videoDetailRow("URL", value: url.absoluteString)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder func videoDetailGroupHeading(_ heading: String) -> some View {
        Text(heading.uppercased())
            .font(.footnote)
            .foregroundColor(.secondary)
    }

    @ViewBuilder func videoDetailRow(_ detail: String, value: String) -> some View {
        HStack {
            Text(detail)
                .foregroundColor(.secondary)
            Spacer()
            let value = Text(value)
            if #available(iOS 15.0, macOS 12.0, *) {
                value
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
            } else {
                value
            }
        }
        .font(.caption)
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
                    Text("1,234M").redacted(reason: .placeholder)
                }

                Image(systemName: "hand.thumbsup")

                if let likes = video?.likesCount, player.videoBeingOpened.isNil {
                    Text(likes)
                } else {
                    Text("1,234M").redacted(reason: .placeholder)
                }

                if Defaults[.enableReturnYouTubeDislike] {
                    Image(systemName: "hand.thumbsdown")

                    if let dislikes = video?.dislikesCount, player.videoBeingOpened.isNil {
                        Text(dislikes)
                    } else {
                        Text("1,234M").redacted(reason: .placeholder)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }

    func videoDetail(label: String, value: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: symbol)

                Text(label.uppercased())
            }
            .font(.system(size: 9))
            .opacity(0.6)

            Text(value)
        }

        .frame(maxWidth: 100)
    }
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(sidebarQueue: true, fullScreen: .constant(false))
            .injectFixtureEnvironmentObjects()
    }
}
