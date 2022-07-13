import Defaults
import Foundation
import SwiftyJSON

final class CommentsModel: ObservableObject {
    @Published var all = [Comment]()

    @Published var nextPage: String?
    @Published var firstPage = true

    @Published var loaded = false
    @Published var disabled = false

    @Published var replies = [Comment]()
    @Published var repliesPageID: String?
    @Published var repliesLoaded = false

    var player: PlayerModel!

    var instance: Instance? {
        player.accounts.current?.instance
    }

    var nextPageAvailable: Bool {
        !(nextPage?.isEmpty ?? true)
    }

    func load(page: String? = nil) {
        guard let video = player.currentVideo else { return }

        if !firstPage && !nextPageAvailable {
            return
        }

        firstPage = page.isNil || page!.isEmpty

        player.accounts.api.comments(video.videoID, page: page)?
            .load()
            .onSuccess { [weak self] response in
                if let page: CommentsPage = response.typedContent() {
                    self?.all += page.comments
                    self?.nextPage = page.nextPage
                    self?.disabled = page.disabled
                }
            }
            .onFailure { [weak self] requestError in
                self?.disabled = !requestError.json.dictionaryValue["error"].isNil
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

        player.accounts.api.comments(player.currentVideo!.videoID, page: page)?
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
