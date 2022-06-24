import SDWebImageSwiftUI
import SwiftUI

struct CommentView: View {
    let comment: Comment
    @Binding var repliesID: Comment.ID?

    @State private var subscribed = false

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<CommentsModel> private var comments
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<SubscriptionsModel> private var subscriptions

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center, spacing: 10) {
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
                            .scaleEffect(progressViewScale, anchor: .center)
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
        WebImage(url: URL(string: comment.authorAvatarURL)!)
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
                .foregroundColor(.secondary)
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
                .font(.system(size: 12))
                #endif
            }
        }
        .foregroundColor(.secondary)
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
            .padding(10)
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

    private var progressViewScale: Double {
        #if os(macOS)
            0.4
        #else
            0.6
        #endif
    }

    private var repliesList: some View {
        Group {
            let last = comments.replies.last
            ForEach(comments.replies) { comment in
                CommentView(comment: comment, repliesID: $repliesID)
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
            let text = Text(comment.text)
            #if os(macOS)
                .font(.system(size: 14))
            #elseif os(iOS)
                .font(.system(size: 15))
            #endif
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if #available(iOS 15.0, macOS 12.0, *) {
                text
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
            } else {
                text
            }
        }
    }

    private func openChannelAction() {
        NavigationModel.openChannel(
            comment.channel,
            player: player,
            recents: recents,
            navigation: navigation
        )
    }
}

struct CommentView_Previews: PreviewProvider {
    static var fixture: Comment {
        Comment.fixture
    }

    static var previews: some View {
        CommentView(comment: fixture, repliesID: .constant(fixture.id))
            .environmentObject(SubscriptionsModel())
            .padding(5)
    }
}
