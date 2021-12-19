import Defaults
import Foundation
import SwiftyJSON

final class CommentsModel: ObservableObject {
    @Published var all = [Comment]()

    @Published var nextPage: String?
    @Published var firstPage = true

    @Published var loading = false
    @Published var loaded = false
    @Published var disabled = false

    @Published var replies = [Comment]()
    @Published var repliesPageID: String?
    @Published var repliesLoaded = false

    var player: PlayerModel!

    static var instance: Instance? {
        InstancesModel.find(Defaults[.commentsInstanceID])
    }

    var api: VideosAPI? {
        Self.instance.isNil ? nil : PipedAPI(account: Self.instance!.anonymousAccount)
    }

    static var enabled: Bool {
        !instance.isNil
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
        guard Self.enabled, !loading else {
            return
        }

        reset()

        loading = true

        guard !Self.instance.isNil,
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
                self?.loading = false
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

        if page == repliesPageID {
            return
        }

        replies = []
        repliesPageID = page
        repliesLoaded = false

        api?.comments(player.currentVideo!.videoID, page: page)?
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
        loading = false
        replies = []
        repliesLoaded = false
    }
}
