//
//  ExpandedCommentsView.swift
//  Yattee
//
//  Full-screen comments overlay with close button.
//

import SwiftUI

struct ExpandedCommentsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let videoID: String
    let onClose: () -> Void
    var onDismissOffsetChanged: ((CGFloat) -> Void)? = nil
    var onDismissGestureEnded: ((CGFloat) -> Void)? = nil
    var dismissThreshold: CGFloat = 30

    // Panel resize drag callbacks
    var onDragChanged: ((CGFloat) -> Void)? = nil
    var onDragEnded: ((CGFloat, CGFloat) -> Void)? = nil

    @State private var showScrollButton = false
    @State private var scrollToTopTrigger: Int = 0
    @State private var scrollBounceOffset: CGFloat = 0
    @State private var isDismissThresholdReached = false

    private var playerState: PlayerState? { appEnvironment?.playerService.state }
    private var contentService: ContentService? { appEnvironment?.contentService }
    private var instancesManager: InstancesManager? { appEnvironment?.instancesManager }

    private var comments: [Comment] { playerState?.comments ?? [] }
    private var commentsState: CommentsLoadState { playerState?.commentsState ?? .idle }
    private var videoSource: ContentSource? { playerState?.currentVideo?.id.source }

    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.black
        #endif
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 5)
            .padding(.bottom, 2)
    }

    /// Whether drag handle should be shown (only when resize callbacks are provided)
    private var showDragHandle: Bool {
        onDragChanged != nil || onDragEnded != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Invisible anchor for scroll-to-top
                    Color.clear
                        .frame(height: 0)
                        .id("commentsTop")

                    // Top padding so content isn't initially obscured by drag handle
                    #if os(iOS)
                    if showDragHandle {
                        Color.clear
                            .frame(height: 17)
                    }
                    #endif

                    // Header - height matches the floating X button (52pt)
                    Text(String(localized: "player.comments"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(height: 52, alignment: .center)
                        .padding(.horizontal)
                        .padding(.top, 16)

                    // Comments content
                    commentsContent
                        .padding(.horizontal)
                }
            }
            #if os(iOS)
            .modifier(CommentsScrollDetectionModifier(
                showScrollButton: $showScrollButton,
                scrollBounceOffset: $scrollBounceOffset,
                isDismissThresholdReached: $isDismissThresholdReached,
                dismissThreshold: dismissThreshold,
                onDismissOffsetChanged: onDismissOffsetChanged,
                onDismissGestureEnded: onDismissGestureEnded,
                onThresholdCrossed: {
                    appEnvironment?.settingsManager.triggerHapticFeedback(for: .commentsDismiss)
                }
            ))
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: 0)
            }
            .animation(.easeInOut(duration: 0.2), value: showScrollButton)
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("commentsTop", anchor: .top)
                }
            }
        }

            // Drag handle overlay for panel resizing (only in portrait mode with callbacks)
            #if os(iOS)
            if showDragHandle {
                VStack(spacing: 0) {
                    dragHandle
                    Spacer()
                }
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(alignment: .top) {
                    LinearGradient(
                        colors: [backgroundColor, backgroundColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 50)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            onDragChanged?(value.translation.height)
                        }
                        .onEnded { value in
                            onDragEnded?(value.translation.height, value.predictedEndTranslation.height)
                        }
                )
            }
            #endif
        }
        .background {
            #if os(iOS)
            Color(.systemBackground)
            #elseif os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color.black
            #endif
        }
        // Top and bottom fade gradients (below buttons)
        .overlay {
            VStack(spacing: 0) {
                // Top fade (skip when drag handle is shown - it provides its own fade)
                #if os(iOS)
                if !showDragHandle {
                    LinearGradient(
                        colors: [backgroundColor, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }
                #else
                LinearGradient(
                    colors: [backgroundColor, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                #endif

                Spacer()

                // Bottom fade
                LinearGradient(
                    colors: [.clear, backgroundColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }
            .allowsHitTesting(false)
        }
        // Buttons on top of fade gradients
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.trailing, 16)
                .padding(.top, 16)
        }
        .overlay(alignment: .bottomTrailing) {
            if showScrollButton {
                scrollToTopButton
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var scrollToTopButton: some View {
        Button {
            scrollToTopTrigger += 1
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .padding(10)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(.regular, in: .circle, fallback: .thinMaterial)
        .contentShape(Circle())
        .padding(.trailing, 16)
        .padding(.bottom, 32)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var commentsContent: some View {
        switch commentsState {
        case .idle, .loading:
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 32)

        case .disabled:
            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "comments.disabled"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)

        case .error:
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "comments.error"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(String(localized: "common.retry")) {
                    Task { await loadComments() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)

        case .loaded, .loadingMore:
            if comments.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "comments.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(comments) { comment in
                        CommentView(comment: comment, videoID: videoID, source: videoSource)
                            .onAppear {
                                if comment.id == comments.last?.id,
                                   playerState?.commentsContinuation != nil,
                                   commentsState == .loaded {
                                    Task { await loadMoreComments() }
                                }
                            }

                        if comment.id != comments.last?.id {
                            Divider()
                        }
                    }

                    if commentsState == .loadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 16)
                            Spacer()
                        }
                    }

                    // Bottom padding for safe area
                    Spacer()
                        .frame(height: 60)
                }
            }
        }
    }

    @ViewBuilder
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: isDismissThresholdReached ? "chevron.down" : "xmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isDismissThresholdReached ? .white : .primary)
                .frame(width: 32, height: 32)
                .padding(10)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassBackground(
            isDismissThresholdReached ? .tinted(.blue) : .regular,
            in: .circle,
            fallback: isDismissThresholdReached ? .ultraThinMaterial : .thinMaterial
        )
        .contentShape(Circle())
        .animation(.easeInOut(duration: 0.15), value: isDismissThresholdReached)
    }

    private func loadComments() async {
        guard let playerState, let contentService, let instancesManager else { return }

        // Don't load comments for non-YouTube videos
        guard let video = playerState.currentVideo, video.supportsComments else {
            playerState.commentsState = .disabled
            return
        }

        // Capture the video ID we're loading comments for
        let requestedVideoID = videoID

        guard let instance = instancesManager.instance(for: video) else { return }

        playerState.commentsState = .loading

        do {
            let page = try await contentService.comments(videoID: videoID, instance: instance, continuation: nil)

            // Validate player is still on the same video
            guard !Task.isCancelled,
                  playerState.currentVideo?.id.videoID == requestedVideoID else { return }

            playerState.comments = page.comments
            playerState.commentsContinuation = page.continuation
            playerState.commentsState = .loaded
        } catch let error as APIError where error == .commentsDisabled {
            guard !Task.isCancelled,
                  playerState.currentVideo?.id.videoID == requestedVideoID else { return }
            playerState.commentsState = .disabled
        } catch {
            guard !Task.isCancelled,
                  playerState.currentVideo?.id.videoID == requestedVideoID else { return }
            playerState.commentsState = .error
        }
    }

    private func loadMoreComments() async {
        guard let playerState, let contentService, let instancesManager else { return }
        guard let continuation = playerState.commentsContinuation else { return }

        // Don't load more comments for non-YouTube videos
        guard let video = playerState.currentVideo, video.supportsComments else {
            return
        }

        // Capture the video ID we're loading comments for
        let requestedVideoID = videoID

        guard let instance = instancesManager.instance(for: video) else { return }

        playerState.commentsState = .loadingMore

        do {
            let page = try await contentService.comments(videoID: videoID, instance: instance, continuation: continuation)

            // Validate player is still on the same video
            guard !Task.isCancelled,
                  playerState.currentVideo?.id.videoID == requestedVideoID else { return }

            playerState.comments.append(contentsOf: page.comments)
            playerState.commentsContinuation = page.continuation
            playerState.commentsState = .loaded
        } catch {
            guard !Task.isCancelled,
                  playerState.currentVideo?.id.videoID == requestedVideoID else { return }
            // Don't change state to error on load more failure
            playerState.commentsState = .loaded
        }
    }
}

// MARK: - Scroll Fade Overlay

/// A view modifier that applies a gradient fade overlay to the top and bottom edges of a scroll view.
private struct ScrollFadeOverlayModifier: ViewModifier {
    let fadeHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                // Top gradient fade
                LinearGradient(
                    colors: [backgroundColor, .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                // Bottom gradient fade
                LinearGradient(
                    colors: [.clear, backgroundColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: fadeHeight)
                .allowsHitTesting(false)
            }
    }

    private var backgroundColor: Color {
        #if os(iOS)
        Color(.systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.black
        #endif
    }
}

private extension View {
    func scrollFadeMask(fadeHeight: CGFloat = 24) -> some View {
        modifier(ScrollFadeOverlayModifier(fadeHeight: fadeHeight))
    }
}

// MARK: - Scroll Detection

#if os(iOS)
private struct CommentsScrollDetectionModifier: ViewModifier {
    @Binding var showScrollButton: Bool
    @Binding var scrollBounceOffset: CGFloat
    @Binding var isDismissThresholdReached: Bool
    var dismissThreshold: CGFloat
    var onDismissOffsetChanged: ((CGFloat) -> Void)?
    var onDismissGestureEnded: ((CGFloat) -> Void)?
    var onThresholdCrossed: (() -> Void)?

    @State private var currentOverscroll: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    @State private var isUserDragging = false

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, newValue in
                    // Track scroll button visibility
                    let shouldShow = newValue > 100
                    if shouldShow != showScrollButton {
                        showScrollButton = shouldShow
                    }

                    // Track overscroll (negative contentOffset = pulling down at top)
                    if newValue < 0 {
                        currentOverscroll = -newValue
                        scrollBounceOffset = currentOverscroll
                        onDismissOffsetChanged?(currentOverscroll)

                        // Only show threshold feedback when user is actively dragging
                        if isUserDragging {
                            let thresholdReached = currentOverscroll >= dismissThreshold
                            if thresholdReached != isDismissThresholdReached {
                                isDismissThresholdReached = thresholdReached
                                // Haptic feedback when crossing threshold
                                if thresholdReached && !hasTriggeredHaptic {
                                    onThresholdCrossed?()
                                    hasTriggeredHaptic = true
                                }
                            }
                        }
                    } else if currentOverscroll > 0 {
                        currentOverscroll = 0
                        scrollBounceOffset = 0
                        onDismissOffsetChanged?(0)
                        isDismissThresholdReached = false
                        hasTriggeredHaptic = false
                    }
                }
                .onScrollPhaseChange { oldPhase, newPhase, _ in
                    // Track when user is actively dragging
                    isUserDragging = (newPhase == .interacting)

                    // When user releases after overscrolling
                    if oldPhase == .interacting && newPhase != .interacting {
                        if currentOverscroll > 0 {
                            onDismissGestureEnded?(currentOverscroll)
                        }
                        // Reset threshold state after gesture ends
                        isDismissThresholdReached = false
                        hasTriggeredHaptic = false
                    }
                }
        } else {
            content
        }
    }
}
#endif
