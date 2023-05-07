import SwiftUI

struct CommentsView: View {
    @State private var repliesID: Comment.ID?

    @ObservedObject private var comments = CommentsModel.shared

    var body: some View {
        Group {
            if comments.disabled {
                NoCommentsView(text: "Comments are disabled".localized(), systemImage: "xmark.circle.fill")
            } else if comments.loaded && comments.all.isEmpty {
                NoCommentsView(text: "No comments".localized(), systemImage: "0.circle.fill")
            } else if !comments.loaded {
                PlaceholderProgressView()
            } else {
                let last = comments.all.last
                LazyVStack {
                    ForEach(comments.all) { comment in
                        CommentView(comment: comment, repliesID: $repliesID)
                            .onAppear {
                                comments.loadNextPageIfNeeded(current: comment)
                            }
                            .borderBottom(height: comment != last ? 0.5 : 0, color: Color("ControlsBorderColor"))
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
