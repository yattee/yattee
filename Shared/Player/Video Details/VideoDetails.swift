import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoDetails: View {
    struct TitleView: View {
        @ObservedObject private var model = PlayerModel.shared
        @State private var titleSize = CGSize.zero

        var video: Video? { model.videoForDisplay }

        var body: some View {
            HStack(spacing: 0) {
                Text(model.videoForDisplay?.displayTitle ?? "Not playing")
                    .font(.title3.bold())
                    .lineLimit(4)
            }
            .padding(.vertical, 4)
        }
    }

    struct ChannelView: View {
        @ObservedObject private var model = PlayerModel.shared

        var video: Video? { model.videoForDisplay }

        var body: some View {
            HStack {
                Button {
                    guard let channel = video?.channel else { return }
                    NavigationModel.shared.openChannel(channel, navigationStyle: .sidebar)
                } label: {
                    ChannelAvatarView(
                        channel: video?.channel,
                        video: video
                    )
                    .frame(maxWidth: 40, maxHeight: 40)
                    .padding(.trailing, 5)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.videoForDisplay?.channel.name ?? "Yattee")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let video, !video.isLocal {
                            Group {
                                Text("•")

                                HStack(spacing: 2) {
                                    Image(systemName: "person.2.fill")

                                    if let channel = model.videoForDisplay?.channel {
                                        if let subscriptions = channel.subscriptionsString {
                                            Text(subscriptions)
                                        } else {
                                            Text("1234").redacted(reason: .placeholder)
                                        }
                                    }
                                }
                            }
                            .font(.caption2)
                        }
                    }
                    .foregroundColor(.secondary)

                    if video != nil {
                        VideoMetadataView()
                    }
                }
            }
        }
    }

    struct VideoMetadataView: View {
        @ObservedObject private var model = PlayerModel.shared
        @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike

        var video: Video? { model.videoForDisplay }

        var body: some View {
            HStack(spacing: 4) {
                publishedDateSection

                Text("•")

                HStack(spacing: 4) {
                    if model.videoBeingOpened != nil || video?.viewsCount != nil {
                        Image(systemName: "eye")
                    }

                    if let views = video?.viewsCount {
                        Text(views)
                    } else if model.videoBeingOpened != nil {
                        Text("123").redacted(reason: .placeholder)
                    }

                    if model.videoBeingOpened != nil || video?.likesCount != nil {
                        Image(systemName: "hand.thumbsup")
                    }

                    if let likes = video?.likesCount, !likes.isEmpty {
                        Text(likes)
                    } else {
                        Text("123").redacted(reason: .placeholder)
                    }

                    if enableReturnYouTubeDislike {
                        if model.videoBeingOpened != nil || video?.dislikesCount != nil {
                            Image(systemName: "hand.thumbsdown")
                        }

                        if let dislikes = video?.dislikesCount, !dislikes.isEmpty {
                            Text(dislikes)
                        } else {
                            Text("123").redacted(reason: .placeholder)
                        }
                    }
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        var publishedDateSection: some View {
            Group {
                if let video {
                    HStack(spacing: 4) {
                        if let published = video.publishedDate {
                            Text(published)
                        } else {
                            Text("1 wk ago").redacted(reason: .placeholder)
                        }
                    }
                }
            }
        }
    }

    enum DetailsPage: String, CaseIterable, Defaults.Serializable {
        case info, comments, queue

        var title: String {
            rawValue.capitalized.localized()
        }
    }

    var video: Video?

    @Binding var fullScreen: Bool
    @Binding var sidebarQueue: Bool

    @State private var detailsSize = CGSize.zero
    @State private var detailsVisibility = Constants.detailsVisibility
    @State private var subscribed = false
    @State private var subscriptionToggleButtonDisabled = false
    @State private var page = DetailsPage.info
    @State private var descriptionExpanded = false

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
    @Default(.showInspector) private var showInspector
    @Default(.expandVideoDescription) private var expandVideoDescription

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TitleView()
                if video != nil, !video!.isLocal {
                    ChannelView()
                        .layoutPriority(1)
                        .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            #if !os(tvOS)
                .tapRecognizer(
                    tapSensitivity: 0.2,
                    doubleTapAction: {
                        withAnimation(.default) {
                            fullScreen.toggle()
                        }
                    }
                )
            #endif

            VideoActions(video: player.videoForDisplay)
                .padding(.vertical, 5)
                .frame(maxHeight: 50)
                .frame(maxWidth: .infinity)
                .borderTop(height: 0.5, color: Color("ControlsBorderColor"))
                .borderBottom(height: 0.5, color: Color("ControlsBorderColor"))
                .animation(nil, value: player.currentItem)
                .frame(minWidth: 0, maxWidth: .infinity)

            pageView
            #if os(iOS)
            .opacity(detailsVisibility ? 1 : 0)
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

    @ViewBuilder var pageMenu: some View {
        Picker("Page", selection: $page) {
            ForEach(DetailsPage.allCases.filter { pageAvailable($0) }, id: \.rawValue) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    func pageAvailable(_ page: DetailsPage) -> Bool {
        guard let video else { return false }

        switch page {
        case .queue:
            return !sidebarQueue && player.isAdvanceToNextItemAvailable
        default:
            return !video.isLocal
        }
    }

    var pageView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack {
                pageMenu
                    .padding(5)

                switch page {
                case .info:
                    Group {
                        if let video {
                            VStack(alignment: .leading, spacing: 10) {
                                if !player.videoBeingOpened.isNil && (video.description.isNil || video.description!.isEmpty) {
                                    VStack {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                    }
                                    .frame(maxWidth: .infinity)
                                } else if let description = video.description, !description.isEmpty {
                                    Section(header: descriptionHeader) {
                                        VideoDescription(video: video, detailsSize: detailsSize, expand: $descriptionExpanded)
                                            .padding(.horizontal)
                                    }
                                } else if !video.isLocal {
                                    Text("No description")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal)
                                }

                                if player.videoBeingOpened.isNil,
                                   !video.isLocal,
                                   !video.chapters.isEmpty
                                {
                                    Section(header: chaptersHeader) {
                                        ChaptersView()
                                    }
                                }

                                if player.videoBeingOpened.isNil,
                                   video.isLocal || showInspector == .always
                                {
                                    InspectorView(video: player.videoForDisplay)
                                        .padding(.horizontal)
                                }

                                if player.videoBeingOpened.isNil,
                                   !sidebarQueue,
                                   !(player.videoForDisplay?.related.isEmpty ?? true)
                                {
                                    RelatedView()
                                        .padding(.horizontal)
                                        .padding(.top, 20)
                                }
                            }
                            .padding(.bottom, 60)
                        }
                    }
                    .onAppear {
                        if video != nil, !pageAvailable(page) {
                            page = .info
                        }
                    }
                    .transition(.opacity)
                    .animation(nil, value: player.currentItem)
                    #if os(iOS)
                        .frame(maxWidth: YatteeApp.isForPreviews ? .infinity : maxWidth)
                    #endif

                case .queue:
                    PlayerQueueView(sidebarQueue: false)
                        .padding(.horizontal)

                case .comments:
                    CommentsView(embedInScrollView: false)
                        .onAppear {
                            comments.loadIfNeeded()
                        }
                }
            }
        }
        #if os(iOS)
        .onAppear {
            if fullScreen {
                if let video, video.isLocal {
                    page = .info
                }
                detailsVisibility = true
                return
            }
            Delay.by(0.8) { withAnimation(.easeIn(duration: 0.25)) { self.detailsVisibility = true } }
        }
        #endif

        .onChange(of: player.queue) { _ in
            if video != nil, !pageAvailable(page) {
                page = .info
            }
        }
    }

    var descriptionHeader: some View {
        HStack {
            Text("Description".localized())

            if !expandVideoDescription, !descriptionExpanded {
                Spacer()
                Image(systemName: "arrow.up.and.down")
                    .imageScale(.small)
            }
        }
        .padding(.horizontal)
        .font(.caption)
        .foregroundColor(.secondary)
    }

    var chaptersHeader: some View {
        Text("Chapters".localized())
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(video: .fixture, fullScreen: .constant(false), sidebarQueue: .constant(false))
    }
}
