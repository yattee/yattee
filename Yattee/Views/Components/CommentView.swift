//
//  CommentView.swift
//  Yattee
//
//  View displaying a single comment.
//

import SwiftUI
import NukeUI

struct CommentView: View {
    let comment: Comment
    let videoID: String?
    let source: ContentSource?
    let isReply: Bool

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var replies: [Comment] = []
    @State private var isLoadingReplies = false
    @State private var showReplies = false
    @State private var repliesContinuation: String?

    private var contentService: ContentService? { appEnvironment?.contentService }
    private var instancesManager: InstancesManager? { appEnvironment?.instancesManager }
    private var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }
    private var accentColor: Color { appEnvironment?.settingsManager.accentColor.color ?? .accentColor }

    init(comment: Comment, videoID: String? = nil, source: ContentSource? = nil, isReply: Bool = false) {
        self.comment = comment
        self.videoID = videoID
        self.source = source
        self.isReply = isReply
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Author avatar
                authorAvatar

                VStack(alignment: .leading, spacing: 4) {
                    // Author name and badges
                    authorInfo

                    // Comment content
                    Text(comment.content)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        #if !os(tvOS)
                        .textSelection(.enabled)
                        #endif

                    // Metadata row
                    metadataRow
                }
            }
            .padding(.vertical, 8)

            // Replies section (only for top-level comments)
            if !isReply && comment.replyCount > 0 {
                repliesSection
            }
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        Button {
            navigateToChannel()
        } label: {
            LazyImage(url: comment.author.thumbnailURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay {
                            Text(String(comment.author.name.prefix(1)))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var authorInfo: some View {
        HStack(spacing: 4) {
            Text(comment.author.name)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(comment.isCreatorComment ? accentColor : .primary)

            if comment.isCreatorComment {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(accentColor)
            }

            if comment.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func navigateToChannel() {
        guard let source, !comment.author.id.isEmpty else { return }
        // Set collapsing first so mini player shows video immediately
        navigationCoordinator?.isPlayerCollapsing = true
        navigationCoordinator?.isPlayerExpanded = false
        navigationCoordinator?.navigate(to: .channel(comment.author.id, source))
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(spacing: 12) {
            // Published time
            if let publishedText = comment.formattedPublishedDate {
                Text(publishedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Like count
            if let likeCount = comment.formattedLikeCount {
                HStack(spacing: 2) {
                    Image(systemName: "hand.thumbsup")
                        .font(.caption2)
                    Text(likeCount)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

            // Creator heart
            if comment.hasCreatorHeart {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Replies Section

    @ViewBuilder
    private var repliesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle replies button
            Button {
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
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .rotationEffect(.degrees(showReplies ? -180 : 0))
                    Text(String(localized: "comments.showReplies \(comment.replyCount)"))
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .padding(.leading, 44) // Align with comment content (avatar width + spacing)
            .padding(.bottom, 8)

            // Replies list
            if showReplies {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(replies) { reply in
                        CommentView(comment: reply, source: source, isReply: true)
                            .padding(.leading, 44)

                        if reply.id != replies.last?.id {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }

                    // Load more replies
                    if isLoadingReplies {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                        .padding(.leading, 44)
                    } else if repliesContinuation != nil {
                        Button {
                            Task { await loadReplies() }
                        } label: {
                            Text(String(localized: "comments.loadMoreReplies"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(accentColor)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 44)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func loadReplies() async {
        guard let videoID, let contentService, let instancesManager else { return }
        guard let instance = instancesManager.enabledInstances.first(where: \.isYouTubeInstance) else { return }

        // Use the comment's replies continuation, or the stored one for subsequent pages
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
