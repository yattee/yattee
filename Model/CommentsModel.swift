import Defaults
import Foundation
import SwiftyJSON

final class CommentsModel: ObservableObject {
    @Published var all = [Comment]()
    @Published var replies = [Comment]()

    @Published var nextPage: String?
    @Published var firstPage = true

    @Published var loaded = false

    var accounts: AccountsModel!
    var player: PlayerModel!

    static var enabled: Bool {
        !Defaults[.commentsInstanceID].isNil && !Defaults[.commentsInstanceID]!.isEmpty
    }

    var nextPageAvailable: Bool {
        !(nextPage?.isEmpty ?? true)
    }

    func load(page: String? = nil) {
        guard Self.enabled else {
            return
        }

        loaded = false
        clear()

        guard let instance = InstancesModel.find(Defaults[.commentsInstanceID]),
              !player.currentVideo.isNil
        else {
            return
        }

        firstPage = page.isNil || page!.isEmpty

        PipedAPI(account: instance.anonymousAccount).comments(player.currentVideo!.videoID, page: page)?
            .load()
            .onSuccess { [weak self] response in
                if let page: CommentsPage = response.typedContent() {
                    self?.all = page.comments
                    self?.nextPage = page.nextPage
                }
            }
            .onCompletion { [weak self] _ in
                self?.loaded = true
            }
    }

    func loadNextPage() {
        load(page: nextPage)
    }

    func loadReplies(page: String) {
        guard !player.currentVideo.isNil else {
            return
        }

        replies = []

        accounts.api.comments(player.currentVideo!.videoID, page: page)?.load().onSuccess { response in
            if let page: CommentsPage = response.typedContent() {
                self.replies = page.comments
            }
        }
    }

    func clear() {
        all = []
        replies = []
        firstPage = true
        nextPage = nil
        loaded = false
    }
}
