import SwiftUI

struct CommentsView: View {
    @State private var repliesID: Comment.ID?

    @EnvironmentObject<CommentsModel> private var comments

    var body: some View {
        Group {
            if comments.disabled {
                Text("Comments are disabled for this video")
                    .foregroundColor(.secondary)
            } else if comments.loaded && comments.all.isEmpty {
                Text("No comments")
                    .foregroundColor(.secondary)
            } else if !comments.loaded {
                PlaceholderProgressView()
                    .onAppear {
                        comments.load()
                    }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading) {
                        let last = comments.all.last
                        ForEach(comments.all) { comment in
                            CommentView(comment: comment, repliesID: $repliesID)

                            if comment != last {
                                Divider()
                                    .padding(.vertical, 5)
                            }
                        }

                        HStack {
                            if comments.nextPageAvailable {
                                Button {
                                    repliesID = nil
                                    comments.loadNextPage()
                                } label: {
                                    Label("Show more", systemImage: "arrow.turn.down.right")
                                }
                            }

                            if !comments.firstPage {
                                Button {
                                    repliesID = nil
                                    comments.load(page: nil)
                                } label: {
                                    Label("Show first", systemImage: "arrow.turn.down.left")
                                }
                            }
                        }
                        .font(.system(size: 13))
                        .buttonStyle(.plain)
                        .padding(.vertical, 8)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

struct CommentsView_Previews: PreviewProvider {
    static var previews: some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            CommentsView()
                .previewInterfaceOrientation(.landscapeRight)
                .injectFixtureEnvironmentObjects()
        }

        CommentsView()
            .injectFixtureEnvironmentObjects()
    }
}
