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
struct TVDetailsPanel: View {
    let video: Video?
    let onDismiss: () -> Void

    @Environment(\.appEnvironment) private var appEnvironment

    /// Tab selection for Info / Comments.
    @State private var selectedTab: TVDetailsTab = .info

    /// Focus state for interactive elements.
    @FocusState private var focusedItem: TVDetailsFocusItem?

    /// Whether description scroll is locked (prevents focus from leaving description).
    @State private var isDescriptionScrollLocked = false

    /// Comments state
    @State private var comments: [Comment] = []
    @State private var commentsState: CommentsLoadState = .idle
    @State private var commentsContinuation: String?

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 80, height: 6)
                .padding(.top, 20)

            // Tab picker (hidden when description scroll is locked)
            if !isDescriptionScrollLocked {
                Picker("", selection: $selectedTab) {
                    Text("Info").tag(TVDetailsTab.info)
                    if video?.supportsComments == true {
                        Text("Comments").tag(TVDetailsTab.comments)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 120)
                .padding(.top, 24)
                .padding(.bottom, 20)
                .focused($focusedItem, equals: .tabPicker)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Content based on selected tab
            Group {
                switch selectedTab {
                case .info:
                    infoContent
                case .comments:
                    commentsContent
                }
            }
            .padding(.horizontal, 88)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height * 0.65)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .frame(maxHeight: .infinity, alignment: .bottom)
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
        .onChange(of: selectedTab) { _, newTab in
            // Reset scroll lock when switching tabs
            if isDescriptionScrollLocked {
                isDescriptionScrollLocked = false
            }
            // Reset comments state when switching to comments tab
            if newTab == .comments && commentsState == .idle {
                // Comments will load via TVCommentsListView's .task
            }
        }
        .onChange(of: video?.supportsComments) { _, supportsComments in
            // If current video doesn't support comments, switch to info tab
            if supportsComments == false && selectedTab == .comments {
                selectedTab = .info
            }
        }
    }

    // MARK: - Info Content

    private var infoContent: some View {
        VStack(spacing: 0) {
            // Top section with title, channel, stats (hidden when description expanded)
            if !isDescriptionScrollLocked {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Video title
                        Text(video?.title ?? "")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .lineLimit(3)
                            .foregroundStyle(.white)

                        // Channel info row
                        channelRow

                        // Stats row
                        statsRow
                    }
                    .padding(.vertical, 16)
                }
                .frame(height: 180)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Description - expands to fill when locked
            if let description = video?.description, !description.isEmpty {
                TVScrollableDescription(
                    description: description,
                    focusedItem: $focusedItem,
                    isScrollLocked: $isDescriptionScrollLocked
                )
                .padding(.top, isDescriptionScrollLocked ? 24 : 8)
            }

            if isDescriptionScrollLocked {
                Spacer()
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
                    navigateToChannel(video.author)
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
                Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
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
                TVCommentsListView(
                    videoID: videoID,
                    comments: $comments,
                    commentsState: $commentsState,
                    commentsContinuation: $commentsContinuation
                )
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

    private func navigateToChannel(_ author: Author) {
        // Close the player and navigate to channel
        onDismiss()
        appEnvironment?.navigationCoordinator.isPlayerExpanded = false

        // Navigate to channel view
        // This would need to be implemented based on your navigation system
    }
}

// MARK: - Supporting Types

/// Tabs for the details panel.
enum TVDetailsTab: String, CaseIterable {
    case info
    case comments
}

/// Focus items for the details panel.
enum TVDetailsFocusItem: Hashable {
    case tabPicker
    case channelButton
    case description
}

/// Scrollable description view with click-to-lock scrolling.
/// When locked, expands to fill available space for easier reading.
struct TVScrollableDescription: View {
    let description: String
    @FocusState.Binding var focusedItem: TVDetailsFocusItem?
    @Binding var isScrollLocked: Bool

    @State private var scrollOffset: CGFloat = 0
    private let scrollStep: CGFloat = 80
    private let maxScroll: CGFloat = 5000

    /// Height of description area - expands when locked
    private var descriptionHeight: CGFloat {
        isScrollLocked ? 500 : 200
    }

    private var isFocused: Bool {
        focusedItem == .description
    }

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
        .buttonStyle(TVDescriptionButtonStyle(isFocused: isFocused, isLocked: isScrollLocked))
        .focused($focusedItem, equals: .description)
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
            HStack {
                Text("Description")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()

                if isFocused {
                    Text(isScrollLocked ? "↑↓ scroll • click to close" : "click to expand")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Clipped container for scrollable text
            Text(description)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .offset(y: -scrollOffset)
                .frame(height: descriptionHeight, alignment: .top)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? (isLocked ? .white.opacity(0.2) : .white.opacity(0.1)) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isLocked ? .white.opacity(0.5) : .clear, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// tvOS comments list with focusable comment rows.
/// Each comment is focusable to allow one-by-one navigation.
struct TVCommentsListView: View {
    let videoID: String
    @Binding var comments: [Comment]
    @Binding var commentsState: CommentsLoadState
    @Binding var commentsContinuation: String?

    @Environment(\.appEnvironment) private var appEnvironment

    private var contentService: ContentService? { appEnvironment?.contentService }
    private var instancesManager: InstancesManager? { appEnvironment?.instancesManager }

    private var canLoadMore: Bool {
        commentsContinuation != nil && commentsState == .loaded
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
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(comments) { comment in
                TVFocusableCommentView(comment: comment, videoID: videoID)
                    .onAppear {
                        // Load more when reaching near the end
                        if comment.id == comments.last?.id && canLoadMore {
                            Task { await loadMoreComments() }
                        }
                    }

                if comment.id != comments.last?.id {
                    Divider()
                        .background(.white.opacity(0.2))
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
        guard commentsState == .idle else { return }
        guard let contentService, let instancesManager else { return }
        guard let instance = instancesManager.enabledInstances.first(where: \.isYouTubeInstance) else { return }

        commentsState = .loading

        do {
            let page = try await contentService.comments(videoID: videoID, instance: instance, continuation: nil)
            comments = page.comments
            commentsContinuation = page.continuation
            commentsState = .loaded
        } catch let error as APIError where error == .commentsDisabled {
            commentsState = .disabled
        } catch {
            commentsState = .error
        }
    }

    private func loadMoreComments() async {
        guard canLoadMore else { return }
        guard let contentService, let instancesManager else { return }
        guard let instance = instancesManager.enabledInstances.first(where: \.isYouTubeInstance) else { return }

        commentsState = .loadingMore

        do {
            let page = try await contentService.comments(videoID: videoID, instance: instance, continuation: commentsContinuation)
            comments.append(contentsOf: page.comments)
            commentsContinuation = page.continuation
            commentsState = .loaded
        } catch {
            commentsState = .loaded
        }
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
                        .foregroundStyle(.blue)
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
                        .foregroundStyle(.blue)
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
