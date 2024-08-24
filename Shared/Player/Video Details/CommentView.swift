#if os(iOS)
    import ActiveLabel
#endif
import SDWebImageSwiftUI
import SwiftUI

struct CommentView: View {
    let comment: Comment
    @Binding var repliesID: Comment.ID?
    var availableWidth: CGFloat

    @State private var subscribed = false

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigationStyle) private var navigationStyle

    @ObservedObject private var comments = CommentsModel.shared
    var subscriptions = SubscribedChannelsModel.shared

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    ZStack(alignment: .bottomTrailing) {
                        authorAvatar

                        if subscribed {
                            Image(systemName: "star.circle.fill")
                            #if os(tvOS)
                                .background(Color.background(scheme: colorScheme))
                            #else
                                .background(Color.background)
                            #endif
                                .clipShape(Circle())
                                .foregroundColor(.secondary)
                        }
                    }
                    .onAppear {
                        subscribed = subscriptions.isSubscribing(comment.channel.id)
                    }

                    authorAndTime
                }
                .contextMenu {
                    Button(action: openChannelAction) {
                        Label("\(comment.channel.name) Channel", systemImage: "rectangle.stack.fill.badge.person.crop")
                    }
                }

                Spacer()

                Group {
                    #if os(iOS)
                        if horizontalSizeClass == .regular {
                            Group {
                                statusIcons
                                likes
                            }
                        } else {
                            VStack(alignment: .trailing, spacing: 8) {
                                likes
                                statusIcons
                            }
                        }
                    #else
                        statusIcons
                        likes
                    #endif
                }
            }
            #if os(tvOS)
            .font(.system(size: 25).bold())
            #else
            .font(.system(size: 15))
            #endif

            Group {
                commentText

                if comment.hasReplies {
                    HStack(spacing: repliesButtonStackSpacing) {
                        repliesButton

                        ProgressView()
                            .scaleEffect(Constants.progressViewScale, anchor: .center)
                            .opacity(repliesID == comment.id && !comments.repliesLoaded ? 1 : 0)
                            .frame(maxHeight: 0)
                    }

                    if comment.id == repliesID {
                        repliesList
                    }
                }
            }
        }
        #if os(tvOS)
        .padding(.horizontal, 20)
        #endif
        .padding(.bottom, 10)
    }

    private var authorAvatar: some View {
        WebImage(url: URL(string: comment.authorAvatarURL), options: [.lowPriority])
            .resizable()
            .placeholder {
                Rectangle().fill(Color("PlaceholderColor"))
            }
            .retryOnAppear(true)
            .indicator(.activity)
            .mask(RoundedRectangle(cornerRadius: 60))
        #if os(tvOS)
            .frame(width: 80, height: 80, alignment: .leading)
            .focusable()
        #else
            .frame(width: 45, height: 45, alignment: .leading)
        #endif
    }

    private var authorAndTime: some View {
        VStack(alignment: .leading) {
            Text(comment.author)
            #if os(tvOS)
                .font(.system(size: 30).bold())
            #else
                .font(.system(size: 14).bold())
            #endif

            Text(comment.time)
                .font(.caption2)
            #if !os(tvOS)
                .foregroundColor(.secondary)
            #endif
        }
        .lineLimit(1)
    }

    private var statusIcons: some View {
        HStack(spacing: 15) {
            if comment.pinned {
                Image(systemName: "pin.fill")
            }
            if comment.hearted {
                Image(systemName: "heart.fill")
            }
        }
        #if !os(tvOS)
        .font(.system(size: 12))
        #endif
        .foregroundColor(.secondary)
    }

    private var likes: some View {
        Group {
            if comment.likeCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "hand.thumbsup")
                    Text("\(comment.likeCount.formattedAsAbbreviation())")
                }
                #if !os(tvOS)
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                #endif
            }
        }
    }

    private var repliesButton: some View {
        Button {
            repliesID = repliesID == comment.id ? nil : comment.id

            guard !repliesID.isNil, !comment.repliesPage.isNil else {
                return
            }

            comments.loadReplies(page: comment.repliesPage!)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: repliesID == comment.id ? "arrow.turn.left.up" : "arrow.turn.right.down")
                Text("Replies")
            }
            #if os(tvOS)
            .font(.system(size: 26))
            .padding(.vertical, 3)
            #endif
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        #if os(tvOS)
            .padding(.leading, 5)
        #else
            .font(.system(size: 13))
            .foregroundColor(.secondary)
        #endif
    }

    private var repliesButtonStackSpacing: Double {
        #if os(tvOS)
            24
        #elseif os(iOS)
            4
        #else
            2
        #endif
    }

    private var repliesList: some View {
        Group {
            let last = comments.replies.last
            ForEach(comments.replies) { comment in
                Self(comment: comment, repliesID: $repliesID, availableWidth: availableWidth - 22)
                #if os(tvOS)
                    .focusable()
                #endif

                if comment != last {
                    Divider()
                        .padding(.vertical, 5)
                }
            }
        }
        .padding(.leading, 22)
    }

    private var commentText: some View {
        Group {
            let rawText = comment.text
            if #available(iOS 15.0, macOS 12.0, *) {
                #if os(iOS)
                    ActiveLabelCommentRepresentable(
                        text: rawText,
                        availableWidth: availableWidth
                    )
                #elseif os(macOS)
                    Text(rawText)
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                #else
                    Text(comment.text)
                #endif
            } else {
                Text(rawText)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openChannelAction() {
        NavigationModel.shared.openChannel(
            comment.channel,
            navigationStyle: navigationStyle
        )
    }
}

#if os(iOS)
    struct ActiveLabelCommentRepresentable: UIViewRepresentable {
        var text: String
        var availableWidth: CGFloat

        @State private var label = ActiveLabel()

        @Environment(\.openURL) private var openURL

        var player = PlayerModel.shared

        func makeUIView(context _: Context) -> some UIView {
            customizeLabel()
            return label
        }

        func updateUIView(_: UIViewType, context _: Context) {
            label.preferredMaxLayoutWidth = availableWidth
        }

        func customizeLabel() {
            label.customize { label in
                label.enabledTypes = [.url, .timestamp]
                label.text = text
                label.font = .systemFont(ofSize: 15)
                label.lineSpacing = 3
                label.preferredMaxLayoutWidth = availableWidth
                label.URLColor = UIColor(Color.accentColor)
                label.timestampColor = UIColor(Color.accentColor)
                label.handleURLTap(urlTapHandler(_:))
                label.handleTimestampTap(timestampTapHandler(_:))
                label.numberOfLines = 0
            }
        }

        private func urlTapHandler(_ url: URL) {
            var urlToOpen = url

            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "yattee"
                if let yatteeURL = components.url {
                    let parser = URLParser(url: urlToOpen, allowFileURLs: false)
                    let destination = parser.destination
                    if destination == .video,
                       parser.videoID == player.currentVideo?.videoID,
                       let time = parser.time
                    {
                        player.backend.seek(to: Double(time), seekType: .userInteracted)
                        return
                    }
                    if destination != nil {
                        urlToOpen = yatteeURL
                    }
                }
            }

            openURL(urlToOpen)
        }

        private func timestampTapHandler(_ timestamp: Timestamp) {
            player.backend.seek(to: timestamp.timeInterval, seekType: .userInteracted)
        }
    }
#endif

struct CommentView_Previews: PreviewProvider {
    static var fixture: Comment {
        Comment.fixture
    }

    static var previews: some View {
        CommentView(comment: fixture, repliesID: .constant(fixture.id), availableWidth: 375)
            .padding(5)
    }
}
