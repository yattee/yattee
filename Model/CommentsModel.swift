import Defaults
import Foundation
import SwiftyJSON

final class CommentsModel: ObservableObject {
    static let shared = CommentsModel()

    @Published var all = [Comment]()

    @Published var nextPage: String?
    @Published var firstPage = true

    @Published var loaded = false
    @Published var disabled = false

    @Published var replies = [Comment]()
    @Published var repliesPageID: String?
    @Published var repliesLoaded = false

    var player = PlayerModel.shared
    var accounts = AccountsModel.shared

    var instance: Instance? {
        accounts.current?.instance
    }

    var nextPageAvailable: Bool {
        !(nextPage?.isEmpty ?? true)
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        load()
    }

    func load(page: String? = nil) {
        guard let video = player.currentVideo else { return }
        guard firstPage || nextPageAvailable else { return }

        player
            .playerAPI(video)?
            .comments(video.videoID, page: page)?
            .load()
            .onSuccess { [weak self] response in
                guard let self else { return }
                if let commentsPage: CommentsPage = response.typedContent() {
                    self.all += commentsPage.comments
                    self.nextPage = commentsPage.nextPage
                    self.disabled = commentsPage.disabled
                }
            }
            .onFailure { [weak self] _ in
                self?.disabled = true
            }
            .onCompletion { [weak self] _ in
                self?.loaded = true
            }
    }

    func loadNextPageIfNeeded(current comment: Comment) {
        let thresholdIndex = all.index(all.endIndex, offsetBy: -5)
        if all.firstIndex(where: { $0 == comment }) == thresholdIndex {
            loadNextPage()
        }
    }

    func loadNextPage() {
        guard nextPageAvailable else { return }
        load(page: nextPage)
    }

    func loadReplies(page: String) {
        guard !player.currentVideo.isNil else {
            return
        }

        if page == repliesPageID {
            return
        }

        replies = []
        repliesPageID = page
        repliesLoaded = false

        accounts.api.comments(player.currentVideo!.videoID, page: page)?
            .load()
            .onSuccess { [weak self] response in
                if let page: CommentsPage = response.typedContent() {
                    self?.replies = page.comments
                    self?.repliesLoaded = true
                }
            }
            .onFailure { [weak self] _ in
                self?.repliesLoaded = true
            }
    }

    func reset() {
        all = []
        disabled = false
        firstPage = true
        nextPage = nil
        loaded = false
        replies = []
        repliesLoaded = false
    }
}
