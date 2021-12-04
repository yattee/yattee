struct Comment: Identifiable, Equatable {
    let id: String
    let author: String
    let authorAvatarURL: String
    let time: String
    let pinned: Bool
    let hearted: Bool
    var likeCount: Int
    let text: String
    let repliesPage: String?
    let channel: Channel

    var hasReplies: Bool {
        !(repliesPage?.isEmpty ?? true)
    }
}
