//
//  TVDetailsPanel.swift
//  Yattee
//
//  Swipe-up details panel for tvOS player showing video info and comments.
//

#if os(tvOS)
import SwiftUI
import NukeUI

/// Details panel that slides up from the bottom showing video information.
/// Pages come from the active tvOS preset's panel settings; the tracks page
/// is not offered on tvOS (the quality panel covers it).
struct TVDetailsPanel: View {
    let video: Video?
    let initialPage: PanelPageType
    let onDismiss: () -> Void

    @Environment(\.appEnvironment) private var appEnvironment

    /// Currently selected page.
    @State private var selectedPage: PanelPageType

    /// Active preset's panel settings; refreshed from the layout service.
    @State private var panelSettings: PanelSettings = PanelSettings.cached

    init(video: Video?, initialPage: PanelPageType = .info, onDismiss: @escaping () -> Void) {
        self.video = video
        self.initialPage = initialPage
        self.onDismiss = onDismiss
        _selectedPage = State(initialValue: initialPage)
    }

    /// Focus state for interactive elements.
    @FocusState private var focusedItem: TVDetailsFocusItem?

    /// Whether description scroll is locked (prevents focus from leaving description).
    @State private var isDescriptionScrollLocked = false

    private var playerState: PlayerState? { appEnvironment?.playerService.state }

    // MARK: - Page Visibility

    /// Config enables a page; runtime hides pages with nothing to show.
    private func isRuntimeVisible(_ pageType: PanelPageType) -> Bool {
        switch pageType {
        case .info:
            return true
        case .comments:
            return video?.supportsComments == true
                && playerState?.commentsState != .disabled
        case .related:
            return !(video?.relatedVideos ?? []).isEmpty
        case .chapters:
            return !(playerState?.chapters ?? []).isEmpty
        case .queue:
            return appEnvironment?.settingsManager.queueEnabled ?? true
        }
    }

    /// Enabled pages that currently have content, in configured order.
    /// Falls back to Info so the panel is never empty.
    private var visiblePages: [PanelPageType] {
        let pages = panelSettings.enabledPages()
            .map(\.pageType)
            .filter { isRuntimeVisible($0) }
        return pages.isEmpty ? [.info] : pages
    }

    /// The page to render: the selection when visible, else the first page.
    private var effectivePage: PanelPageType {
        let pages = visiblePages
        return pages.contains(selectedPage) ? selectedPage : (pages.first ?? .info)
    }

    var body: some View {
        let pages = visiblePages

        VStack(spacing: 0) {
            // Page switcher (hidden when description scroll is locked)
            if pages.count >= 2, !isDescriptionScrollLocked {
                pageSwitcher(pages: pages)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Content for the selected page
            Group {
                switch effectivePage {
                case .info:
                    infoContent
                case .comments:
                    commentsContent
                case .related:
                    TVRelatedPanelList(video: video, onDidSelectVideo: onDismiss)
                case .chapters:
                    TVChaptersPanelList()
                case .queue:
                    TVQueueListView(horizontalPadding: 0)
                }
            }
            .padding(.horizontal, 40)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
        .onExitCommand {
            // If description scroll is locked, unlock it first
            if isDescriptionScrollLocked {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isDescriptionScrollLocked = false
                }
            } else {
                onDismiss()
            }
        }
        .onAppear {
            focusedItem = .tabPicker
        }
        .task {
            await reloadPanelSettings()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerControlsActivePresetDidChange)) { _ in
            Task { await reloadPanelSettings() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .playerControlsPresetsDidChange)) { _ in
            Task { await reloadPanelSettings() }
        }
        .onChange(of: selectedPage) { _, _ in
            // Reset scroll lock when switching pages
            if isDescriptionScrollLocked {
                isDescriptionScrollLocked = false
            }
        }
        .onChange(of: video?.id) { _, _ in
            // New video: fall back to the first configured page.
            if let first = visiblePages.first {
                selectedPage = first
            }
        }
    }

    // MARK: - Page Switcher

    @ViewBuilder
    private func pageSwitcher(pages: [PanelPageType]) -> some View {
        // Segmented control fits up to 4 pages in the half-screen panel;
        // above that a focusable button row keeps labels legible.
        if pages.count <= 4 {
            Picker("", selection: $selectedPage) {
                ForEach(pages, id: \.self) { page in
                    Text(page.displayName).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)
            .focused($focusedItem, equals: .tabPicker)
        } else {
            HStack(spacing: 12) {
                ForEach(pages, id: \.self) { page in
                    Button {
                        selectedPage = page
                    } label: {
                        Label(page.displayName, systemImage: page.systemImage)
                            .font(.callout)
                            .labelStyle(.titleOnly)
                    }
                    .buttonStyle(TVPageSwitcherButtonStyle(isSelected: effectivePage == page))
                    .focused($focusedItem, equals: .pageButton(page))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 40)
            .padding(.bottom, 20)
            .focusSection()
        }
    }

    // MARK: - Panel Settings

    private func reloadPanelSettings() async {
        guard let service = appEnvironment?.playerControlsLayoutService else { return }
        let layout = await service.activeLayout()
        let settings = layout.effectivePanelSettings
        panelSettings = settings
        PanelSettings.cached = settings
    }

    // MARK: - Info Content

    private var infoSettings: InfoPageSettings {
        panelSettings.configuration(for: .info)?.infoSettings ?? InfoPageSettings()
    }

    private var infoContent: some View {
        let settings = infoSettings

        return VStack(spacing: 0) {
            // Top section with title, channel, stats (hidden when description expanded)
            if !isDescriptionScrollLocked {
                VStack(alignment: .leading, spacing: 24) {
                    // Video title
                    Text(video?.title ?? "")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                        .foregroundStyle(.white)

                    // Channel info row
                    if settings.effectiveShowChannelRow {
                        channelRow
                    }

                    // Stats row
                    if settings.effectiveShowStatsRow {
                        statsRow
                    }
                }
                .padding(.vertical, 16)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Description - expands to fill when locked
            if settings.effectiveShowDescription,
               let description = video?.description, !description.isEmpty {
                TVScrollableDescription(
                    description: description,
                    isScrollLocked: $isDescriptionScrollLocked,
                    overlaysDarkBackground: true
                )
                .padding(.top, isDescriptionScrollLocked ? 24 : 8)
            }

        }
        .animation(.easeInOut(duration: 0.25), value: isDescriptionScrollLocked)
    }

    // MARK: - Channel Row

    /// Author enriched with cached channel data (avatar, subscriber count) from local stores.
    private var enrichedAuthor: Author? {
        guard let video else { return nil }
        guard let dataManager = appEnvironment?.dataManager else { return video.author }
        return video.author.enriched(using: dataManager)
    }

    private var channelRow: some View {
        HStack(spacing: 16) {
            // Channel avatar
            if let thumbnailURL = enrichedAuthor?.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(.white.opacity(0.2))
                }
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Channel name
                Text(enrichedAuthor?.name ?? "")
                    .font(.headline)
                    .foregroundStyle(.white)

                // Subscriber count
                if let subscriberCount = enrichedAuthor?.subscriberCount {
                    Text("channel.subscriberCount \(CountFormatter.compact(subscriberCount))")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            // Channel button
            Button {
                // Navigate to channel
                if let video {
                    navigateToChannel(for: video)
                }
            } label: {
                Text(String(localized: "channel.view"))
                    .font(.callout)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .focused($focusedItem, equals: .channelButton)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 32) {
            // Views
            if let viewCount = video?.viewCount {
                Label {
                    Text(CountFormatter.compact(viewCount))
                } icon: {
                    Image(systemName: "eye")
                }
            }

            // Likes
            if let likeCount = video?.likeCount {
                Label {
                    Text(CountFormatter.compact(likeCount))
                } icon: {
                    Image(systemName: "hand.thumbsup")
                }
            }

            // Published date
            if let publishedText = video?.formattedPublishedDate {
                Label {
                    Text(publishedText)
                } icon: {
                    Image(systemName: "calendar")
                }
            }

            // Duration
            if let video, video.duration > 0 {
                Label {
                    Text(video.formattedDuration)
                } icon: {
                    Image(systemName: "clock")
                }
            }

            // Live indicator
            if video?.isLive == true {
                Label("player.live", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.red)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: - Comments Content

    private var commentsContent: some View {
        ScrollView {
            if let videoID = video?.id.videoID {
                TVCommentsListView(videoID: videoID)
                    .padding(.vertical, 16)
            } else {
                Text(String(localized: "comments.unavailable"))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
        }
    }

    // MARK: - Navigation

    private func navigateToChannel(for video: Video) {
        onDismiss()
        appEnvironment?.navigationCoordinator.navigateToChannel(for: video, collapsePlayer: true)
    }
}

// MARK: - Supporting Types

/// Focus items for the details panel.
enum TVDetailsFocusItem: Hashable {
    case tabPicker
    case pageButton(PanelPageType)
    case channelButton
    case description
}

/// Button style for the page switcher row used when more than four pages are
/// enabled. Solid focus fill (materials are invisible over video on Apple TV
/// HD); the selected page keeps a subtle persistent fill.
struct TVPageSwitcherButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.black : (isSelected ? .white : .white.opacity(0.6)))
            .lineLimit(1)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isFocused ? Color.white.opacity(0.92) : (isSelected ? Color.white.opacity(0.2) : .clear))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Scrollable description view with click-to-lock scrolling.
/// When locked, expands to fill available space for easier reading.
struct TVScrollableDescription: View {
    let description: String
    @Binding var isScrollLocked: Bool
    var showsHeader: Bool = true
    /// The player details panel always sits over a dark backdrop, so it keeps
    /// white text; regular pages use adaptive colors for the light scheme.
    var overlaysDarkBackground: Bool = false

    @FocusState private var isFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    private let scrollStep: CGFloat = 80
    private let maxScroll: CGFloat = 5000

    var body: some View {
        Button {
            // Toggle scroll lock on click/select
            withAnimation(.easeInOut(duration: 0.25)) {
                isScrollLocked.toggle()
                if !isScrollLocked {
                    scrollOffset = 0
                }
            }
        } label: {
            descriptionContent
        }
        .buttonStyle(TVDescriptionButtonStyle(isFocused: isFocused, isLocked: isScrollLocked, overlaysDarkBackground: overlaysDarkBackground))
        .focused($isFocused)
        .onMoveCommand { direction in
            guard isScrollLocked else { return }

            switch direction {
            case .down:
                withAnimation(.easeOut(duration: 0.15)) {
                    scrollOffset = min(scrollOffset + scrollStep, maxScroll)
                }
            case .up:
                withAnimation(.easeOut(duration: 0.15)) {
                    scrollOffset = max(scrollOffset - scrollStep, 0)
                }
            default:
                break
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                // Reset lock when losing focus
                withAnimation(.easeInOut(duration: 0.2)) {
                    isScrollLocked = false
                    scrollOffset = 0
                }
            }
        }
    }

    private var descriptionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeader {
                HStack {
                    Text("player.description")
                        .font(.headline)
                        .foregroundStyle(overlaysDarkBackground ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.secondary))

                    Spacer()

                    if isFocused {
                        Text(isScrollLocked ? "player.description.scrollToClose" : "player.description.clickToExpand")
                            .font(.callout)
                            .foregroundStyle(overlaysDarkBackground ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(.tertiary))
                    }
                }
            }

            // Clipped container for scrollable text. The Rectangle owns the
            // layout size (fills available space) so the Text's intrinsic
            // height from .fixedSize doesn't push parents.
            Rectangle()
                .fill(Color.clear)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(overlaysDarkBackground ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.primary))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .offset(y: -scrollOffset)
                }
                .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: isScrollLocked)
    }
}

/// Button style for description view - no default focus highlight.
struct TVDescriptionButtonStyle: ButtonStyle {
    let isFocused: Bool
    let isLocked: Bool
    var overlaysDarkBackground: Bool = false

    private var highlightColor: Color {
        overlaysDarkBackground ? .white : .primary
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? (isLocked ? highlightColor.opacity(0.2) : highlightColor.opacity(0.1)) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isLocked ? highlightColor.opacity(0.5) : .clear, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// tvOS comments list with focusable comment rows.
/// Each comment is focusable to allow one-by-one navigation.
/// Backed by the unified `PlayerState` comments loader shared with iOS/macOS,
/// so a page opened here reuses (and feeds) the same fetched comments.
struct TVCommentsListView: View {
    let videoID: String

    @Environment(\.appEnvironment) private var appEnvironment

    private var contentService: ContentService? { appEnvironment?.contentService }
    private var instancesManager: InstancesManager? { appEnvironment?.instancesManager }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }

    private var comments: [Comment] { playerState?.comments ?? [] }
    private var commentsState: CommentsLoadState { playerState?.commentsState ?? .idle }

    private var canLoadMore: Bool {
        playerState?.commentsContinuation != nil && commentsState == .loaded
    }

    var body: some View {
        Group {
            switch commentsState {
            case .idle, .loading:
                loadingView
            case .disabled:
                disabledView
            case .error:
                errorView
            case .loaded, .loadingMore:
                if comments.isEmpty {
                    emptyView
                } else {
                    commentsList
                }
            }
        }
        .task {
            await loadComments()
        }
    }

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 32)
    }

    private var disabledView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text(String(localized: "comments.disabled"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var errorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text(String(localized: "comments.failedToLoad"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
            Button(String(localized: "common.retry")) {
                Task { await loadComments() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
            Text(String(localized: "comments.empty"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var commentsList: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(comments) { comment in
                TVFocusableCommentView(comment: comment, videoID: videoID)
                    .onAppear {
                        // Load more when reaching near the end
                        if comment.id == comments.last?.id && canLoadMore {
                            Task { await loadMoreComments() }
                        }
                    }
            }

            // Loading more indicator
            if commentsState == .loadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 16)
                    Spacer()
                }
            }
        }
    }

    private func loadComments() async {
        guard commentsState == .idle || commentsState == .error else { return }
        guard let playerState, let contentService, let instancesManager else { return }
        await playerState.loadComments(contentService: contentService, instancesManager: instancesManager)
    }

    private func loadMoreComments() async {
        guard canLoadMore else { return }
        guard let playerState, let contentService, let instancesManager else { return }
        await playerState.loadMoreComments(contentService: contentService, instancesManager: instancesManager)
    }
}

/// Focusable comment view for tvOS.
/// Comments with replies show an expandable button, others have invisible focus placeholder.
struct TVFocusableCommentView: View {
    let comment: Comment
    let videoID: String

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var replies: [Comment] = []
    @State private var isLoadingReplies = false
    @State private var showReplies = false
    @State private var repliesContinuation: String?

    private var contentService: ContentService? { appEnvironment?.contentService }
    private var instancesManager: InstancesManager? { appEnvironment?.instancesManager }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main comment content - always focusable
            Button {
                // Toggle replies if available
                if comment.replyCount > 0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if showReplies {
                            showReplies = false
                        } else {
                            showReplies = true
                            if replies.isEmpty {
                                Task { await loadReplies() }
                            }
                        }
                    }
                }
            } label: {
                commentContent
            }
            .buttonStyle(TVCommentButtonStyle(hasReplies: comment.replyCount > 0))

            // Replies section
            if showReplies && comment.replyCount > 0 {
                repliesSection
            }
        }
    }

    private var commentContent: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar
            LazyImage(url: comment.author.thumbnailURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .overlay {
                            Text(String(comment.author.name.prefix(1)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                // Author name and badges
                HStack(spacing: 4) {
                    Text(comment.author.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    if comment.isCreatorComment {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    if comment.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    // Published time
                    if let publishedText = comment.formattedPublishedDate {
                        Text(publishedText)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                // Comment content
                Text(comment.content)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // Metadata row
                HStack(spacing: 16) {
                    if let likeCount = comment.formattedLikeCount {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.thumbsup")
                                .font(.caption)
                            Text(likeCount)
                                .font(.caption)
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }

                    if comment.hasCreatorHeart {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Replies indicator
                    if comment.replyCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: showReplies ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text("comments.replyCount \(comment.replyCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(replies) { reply in
                TVReplyView(comment: reply)
                    .padding(.leading, 52) // Indent replies

                if reply.id != replies.last?.id {
                    Divider()
                        .background(.white.opacity(0.15))
                        .padding(.leading, 52)
                }
            }

            // Loading indicator
            if isLoadingReplies {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 8)
                    Spacer()
                }
                .padding(.leading, 52)
            }

            // Load more button
            if !isLoadingReplies && repliesContinuation != nil {
                Button {
                    Task { await loadReplies() }
                } label: {
                    Text(String(localized: "comments.loadMoreReplies"))
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 52)
                .padding(.vertical, 8)
            }
        }
    }

    private func loadReplies() async {
        guard let contentService, let instancesManager else { return }
        guard let instance = instancesManager.enabledInstances.first(where: \.isYouTubeInstance) else { return }

        let continuation = replies.isEmpty ? comment.repliesContinuation : repliesContinuation
        guard let continuation else { return }

        isLoadingReplies = true

        do {
            let page = try await contentService.comments(videoID: videoID, instance: instance, continuation: continuation)
            replies.append(contentsOf: page.comments)
            repliesContinuation = page.continuation
        } catch {
            // Silently fail for replies
        }

        isLoadingReplies = false
    }
}

/// Focusable reply view for tvOS.
struct TVReplyView: View {
    let comment: Comment

    var body: some View {
        Button {
            // No action for replies, just focusable for navigation
        } label: {
            replyContent
        }
        .buttonStyle(TVCommentButtonStyle(hasReplies: false))
    }

    private var replyContent: some View {
        HStack(alignment: .top, spacing: 10) {
            // Author avatar (smaller for replies)
            LazyImage(url: comment.author.thumbnailURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .overlay {
                            Text(String(comment.author.name.prefix(1)))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                // Author name
                HStack(spacing: 4) {
                    Text(comment.author.name)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    if comment.isCreatorComment {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                    if let publishedText = comment.formattedPublishedDate {
                        Text("• \(publishedText)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                // Reply content
                Text(comment.content)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                // Likes
                if let likeCount = comment.formattedLikeCount {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.thumbsup")
                            .font(.caption2)
                        Text(likeCount)
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Button style for focusable comments.
struct TVCommentButtonStyle: ButtonStyle {
    let hasReplies: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isFocused ? .white.opacity(0.1) : .clear)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

#endif
