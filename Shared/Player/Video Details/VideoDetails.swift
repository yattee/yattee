import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoDetails: View {
    static let pageMenuID = "pageMenu"

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
        @Binding var detailsVisibility: Bool

        var video: Video? { model.videoForDisplay }

        var body: some View {
            HStack {
                Button {
                    guard let channel = video?.channel else { return }
                    NavigationModel.shared.openChannel(channel, navigationStyle: .sidebar)
                } label: {
                    if detailsVisibility {
                        ChannelAvatarView(
                            channel: video?.channel,
                            video: video
                        )
                    } else {
                        Circle()
                            .foregroundColor(Color("PlaceholderColor"))
                    }
                }
                .frame(width: 40, height: 40)
                .buttonStyle(.plain)
                .padding(.trailing, 5)
                // TODO: when setting tvOS minimum to 16, the platform modifier can be removed
                #if !os(tvOS)
                    .simultaneousGesture(
                        TapGesture() // Ensures the button tap is recognized
                    )
                #endif

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if let name = model.videoForDisplay?.channel.name, !name.isEmpty {
                            Text(name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            // TODO: when setting tvOS minimum to 16, the platform modifier can be removed
                            #if !os(tvOS)
                                .onTapGesture {
                                    guard let channel = video?.channel else { return }
                                    NavigationModel.shared.openChannel(channel, navigationStyle: .sidebar)
                                }
                                .accessibilityAddTraits(.isButton)
                            #endif
                        } else if model.videoBeingOpened != nil {
                            Text("Yattee")
                                .font(.subheadline)
                                .redacted(reason: .placeholder)
                        }

                        if let video, !video.isLocal {
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
    @State private var chaptersExpanded = false

    @Environment(\.navigationStyle) private var navigationStyle
    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var comments = CommentsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    @Default(.enableReturnYouTubeDislike) private var enableReturnYouTubeDislike
    @Default(.playerSidebar) private var playerSidebar
    @Default(.showInspector) private var showInspector
    @Default(.showChapters) private var showChapters
    @Default(.showChapterThumbnails) private var showChapterThumbnails
    @Default(.showChapterThumbnailsOnlyWhenDifferent) private var showChapterThumbnailsOnlyWhenDifferent
    @Default(.showRelated) private var showRelated
    @Default(.showComments) private var showComments
    #if !os(tvOS)
        @Default(.showScrollToTopInComments) private var showScrollToTopInComments
    #endif
    @Default(.expandVideoDescription) private var expandVideoDescription
    @Default(.expandChapters) private var expandChapters

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                TitleView()
                if video != nil, !video!.isLocal {
                    ChannelView(detailsVisibility: $detailsVisibility)
                        .layoutPriority(1)
                        .padding(.bottom, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)

            // TODO: when setting tvOS minimum to 16, the platform modifier can be removed
            #if !os(tvOS)
                .simultaneousGesture( // Simultaneous gesture to prioritize button tap
                    TapGesture(count: 2).onEnded {
                        withAnimation(.default) {
                            fullScreen.toggle()
                        }
                    }
                )
            #endif

            if VideoActions().isAnyActionVisible() {
                VideoActions(video: player.videoForDisplay)
                    .padding(.vertical, 5)
                    .frame(maxHeight: 50)
                    .frame(maxWidth: .infinity)
                    .borderTop(height: 0.5, color: Color("ControlsBorderColor"))
                    .borderBottom(height: 0.5, color: Color("ControlsBorderColor"))
                    .animation(nil, value: player.currentItem)
                    .frame(minWidth: 0, maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 0.5)
                    .frame(maxWidth: .infinity)
                    .background(Color("ControlsBorderColor"))
            }

            ScrollViewReader { proxy in
                pageView
                    .overlay(scrollToTopButton(proxy), alignment: .bottomTrailing)
            }
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
        .onAppear {
            descriptionExpanded = expandVideoDescription
            chaptersExpanded = expandChapters
        }
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
        case .comments:
            return showComments
        default:
            return !video.isLocal
        }
    }

    func infoView(video: Video) -> some View {
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

            if player.videoBeingOpened.isNil {
                if showChapters,
                   !video.isLocal,
                   !video.chapters.isEmpty
                {
                    Section(header: chaptersHeader) {
                        ChaptersView(expand: $chaptersExpanded, chaptersHaveImages: chaptersHaveImages, showThumbnails: showThumbnails)
                    }
                }

                if showInspector == .always || video.isLocal {
                    InspectorView(video: player.videoForDisplay)
                        .padding(.horizontal)
                }

                if showRelated,
                   !sidebarQueue,
                   !(player.videoForDisplay?.related.isEmpty ?? true)
                {
                    RelatedView()
                        .padding(.horizontal)
                        .padding(.top, 20)
                }
            }
        }
        .onAppear {
            if !pageAvailable(page) {
                page = .info
            }
        }
        .transition(.opacity)
        .animation(nil, value: player.currentItem)
        #if os(iOS)
            .frame(maxWidth: YatteeApp.isForPreviews ? .infinity : maxWidth)
        #endif
    }

    var pageView: some View {
        ScrollView(.vertical) {
            LazyVStack {
                pageMenu
                    .id(Self.pageMenuID)
                    .padding(5)

                switch page {
                case .info:
                    if let video = self.video {
                        infoView(video: video)
                    }
                case .queue:
                    PlayerQueueView(sidebarQueue: false)
                        .padding(.horizontal)
                case .comments:
                    if showComments {
                        CommentsView()
                            .onAppear {
                                comments.loadIfNeeded()
                            }
                    }
                }
            }
            .padding(.bottom, 60)
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

    @ViewBuilder func scrollToTopButton(_ proxy: ScrollViewProxy) -> some View {
        #if !os(tvOS)
            if showScrollToTopInComments,
               page == .comments,
               comments.loaded,
               comments.all.count > 3
            {
                Button {
                    withAnimation {
                        proxy.scrollTo(Self.pageMenuID)
                    }
                } label: {
                    Label("Scroll to top", systemImage: "arrow.up")
                        .padding(8)
                        .foregroundColor(.white)
                        .background(Circle().opacity(0.8).foregroundColor(.accentColor))
                }
                .padding()
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
            }
        #endif
    }

    var descriptionHeader: some View {
        #if canImport(UIKit)
            Button(action: {
                descriptionExpanded.toggle()
            }) {
                HStack {
                    Text("Description".localized())
                    Spacer()
                    Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
                .padding(.horizontal)
                .font(.caption)
                .foregroundColor(.secondary)
            }
        #elseif canImport(AppKit)
            HStack {
                Text("Description".localized())
                Spacer()
                Button { descriptionExpanded.toggle()
                } label: {
                    Image(systemName: descriptionExpanded ? "chevron.up" : "chevron.down")
                        .imageScale(.small)
                }
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.secondary)
        #endif
    }

    var chaptersHaveImages: Bool {
        player.videoForDisplay?.chapters.allSatisfy { $0.image != nil } ?? false
    }

    var chapterImagesTheSame: Bool {
        guard let firstChapterURL = player.videoForDisplay?.chapters.first?.image else {
            return false
        }

        return player.videoForDisplay?.chapters.allSatisfy { $0.image == firstChapterURL } ?? false
    }

    var showThumbnails: Bool {
        if !chaptersHaveImages || !showChapterThumbnails {
            return false
        }
        if showChapterThumbnailsOnlyWhenDifferent {
            return !chapterImagesTheSame
        }
        return true
    }

    var chaptersHeader: some View {
        Group {
            if !chaptersHaveImages || !showThumbnails {
                #if canImport(UIKit)
                    Button(action: {
                        chaptersExpanded.toggle()
                    }) {
                        HStack {
                            Text("Chapters".localized())
                            Spacer()
                            Image(systemName: chaptersExpanded ? "chevron.up" : "chevron.down")
                                .imageScale(.small)
                        }
                        .padding(.horizontal)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                #elseif canImport(AppKit)
                    HStack {
                        Text("Chapters".localized())
                        Spacer()
                        Button(action: { chaptersExpanded.toggle() }) {
                            Image(systemName: chaptersExpanded ? "chevron.up" : "chevron.down")
                                .imageScale(.small)
                        }
                    }
                    .padding(.horizontal)
                    .font(.caption)
                    .foregroundColor(.secondary)
                #endif
            } else {
                // No button, just the title when there are images
                Text("Chapters".localized())
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
        }
    }
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(video: .fixture, fullScreen: .constant(false), sidebarQueue: .constant(false))
    }
}
