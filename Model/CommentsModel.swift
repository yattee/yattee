import Defaults
import Foundation
import SwiftyJSON

final class CommentsModel: ObservableObject {
    @Published var all = [Comment]()

    @Published var nextPage: String?
    @Published var firstPage = true

    @Published var loaded = true
    @Published var disabled = false

    @Published var replies = [Comment]()
    @Published var repliesLoaded = false

    var accounts: AccountsModel!
    var player: PlayerModel!

    var instance: Instance? {
        InstancesModel.find(Defaults[.commentsInstanceID])
    }

    var api: VideosAPI? {
        instance.isNil ? nil : PipedAPI(account: instance!.anonymousAccount)
    }

    static var enabled: Bool {
        !Defaults[.commentsInstanceID].isNil && !Defaults[.commentsInstanceID]!.isEmpty
    }

    #if !os(tvOS)
        static var placement: CommentsPlacement {
            Defaults[.commentsPlacement]
        }
    #endif

    var nextPageAvailable: Bool {
        !(nextPage?.isEmpty ?? true)
    }

    func load(page: String? = nil) {
        guard Self.enabled else {
            return
        }

        reset()

        guard !instance.isNil,
              !(player?.currentVideo.isNil ?? true)
        else {
            return
        }

        firstPage = page.isNil || page!.isEmpty

        api?.comments(player.currentVideo!.videoID, page: page)?
            .load()
            .onSuccess { [weak self] response in
                if let page: CommentsPage = response.typedContent() {
                    self?.all = page.comments
                    self?.nextPage = page.nextPage
                    self?.disabled = page.disabled
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
        repliesLoaded = false

        api?.comments(player.currentVideo!.videoID, page: page)?
            .load()
            .onSuccess { [weak self] response in
                if let page: CommentsPage = response.typedContent() {
                    self?.replies = page.comments
                }
            }
            .onCompletion { [weak self] _ in
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
