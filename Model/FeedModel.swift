import Cache
import CoreData
import Foundation
import Siesta
import SwiftyJSON

final class FeedModel: ObservableObject, CacheModel {
    static let shared = FeedModel()

    @Published var isLoading = false
    @Published var videos = [Video]()
    @Published private var page = 1
    @Published var unwatched = [Account: Int]()

    private var cacheModel = FeedCacheModel.shared
    private var accounts = AccountsModel.shared

    var storage: Storage<String, JSON>?

    private var backgroundContext = PersistenceController.shared.container.newBackgroundContext()

    var feed: Resource? {
        accounts.api.feed(page)
    }

    func loadResources(force: Bool = false, onCompletion: @escaping () -> Void = {}) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self else { return }

            if force || self.videos.isEmpty {
                self.loadCachedFeed()
            }

            if self.accounts.app == .invidious {
                // Invidious for some reason won't refresh feed until homepage is loaded
                DispatchQueue.main.async { [weak self] in
                    guard let self, let home = self.accounts.api.home else { return }
                    self.request(home, force: force)?
                        .onCompletion { _ in
                            self.loadFeed(force: force, onCompletion: onCompletion)
                        }
                }
            } else {
                self.loadFeed(force: force, onCompletion: onCompletion)
            }
        }
    }

    func loadFeed(force: Bool = false, paginating: Bool = false, onCompletion: @escaping () -> Void = {}) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.isLoading,
                  let account = self.accounts.current
            else {
                self?.isLoading = false
                onCompletion()
                return
            }

            if paginating {
                self.page += 1
            } else {
                self.page = 1
            }

            let feedBeforeLoad = self.feed
            var request: Request?
            if let feedBeforeLoad {
                request = self.request(feedBeforeLoad, force: force)
            }
            if request != nil {
                self.isLoading = true
            }

            request?
                .onCompletion { _ in
                    self.isLoading = false
                    onCompletion()
                }
                .onSuccess { response in
                    if let videos: [Video] = response.typedContent() {
                        if paginating {
                            self.videos.append(contentsOf: videos)
                        } else {
                            self.videos = videos
                            self.cacheModel.storeFeed(account: account, videos: self.videos)
                            self.calculateUnwatchedFeed()
                        }
                    }
                }
                .onFailure { error in
                    NavigationModel.shared.presentAlert(title: "Could not refresh Subscriptions", message: error.userMessage)
                }
        }
    }

    func reset() {
        videos.removeAll()
        page = 1
    }

    func loadNextPage() {
        guard accounts.app.paginatesSubscriptions, !isLoading else { return }

        loadFeed(force: true, paginating: true)
    }

    func calculateUnwatchedFeed() {
        guard let account = accounts.current else { return }
        let feed = cacheModel.retrieveFeed(account: account)
        guard !feed.isEmpty else { return }
        backgroundContext.perform { [weak self] in
            guard let self else { return }

            let watched = self.watchFetchRequestResult(feed, context: self.backgroundContext).filter { $0.finished }.count
            let unwatched = feed.count - watched

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if unwatched != self.unwatched[account] {
                    self.unwatched[account] = unwatched
                }
            }
        }
    }

    func markAllFeedAsWatched() {
        guard let account = accounts.current else { return }
        guard !videos.isEmpty else { return }

        backgroundContext.perform { [weak self] in
            guard let self else { return }
            self.videos.forEach { Watch.markAsWatched(videoID: $0.videoID, account: account, duration: $0.length, context: self.backgroundContext) }

            self.calculateUnwatchedFeed()
        }
    }

    func markAllFeedAsUnwatched() {
        guard accounts.current != nil,
              !videos.isEmpty else { return }

        backgroundContext.perform { [weak self] in
            guard let self else { return }

            let watches = self.watchFetchRequestResult(self.videos, context: self.backgroundContext)
            watches.forEach { self.backgroundContext.delete($0) }

            try? self.backgroundContext.save()

            self.calculateUnwatchedFeed()
        }
    }

    func watchFetchRequestResult(_ videos: [Video], context: NSManagedObjectContext) -> [Watch] {
        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID IN %@", videos.map(\.videoID) as [String])
        return (try? context.fetch(watchFetchRequest)) ?? []
    }

    func playUnwatchedFeed() {
        guard let account = accounts.current else { return }
        let videos = cacheModel.retrieveFeed(account: account)
        guard !videos.isEmpty else { return }

        let watches = watchFetchRequestResult(videos, context: backgroundContext)
        let watchesIDs = watches.map(\.videoID)
        let unwatched = videos.filter { video in
            if !watchesIDs.contains(video.videoID) {
                return true
            }

            if let watch = watches.first(where: { $0.videoID == video.videoID }),
               watch.finished
            {
                return false
            }

            return true
        }

        guard !unwatched.isEmpty else { return }
        PlayerModel.shared.play(unwatched)
    }

    var feedTime: Date? {
        if let account = accounts.current {
            return cacheModel.getFeedTime(account: account)
        }

        return nil
    }

    var formattedFeedTime: String {
        getFormattedDate(feedTime)
    }

    private func loadCachedFeed() {
        guard let account = accounts.current else { return }
        let cache = cacheModel.retrieveFeed(account: account)
        if !cache.isEmpty {
            DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                self?.videos = cache
            }
        }
    }

    private func request(_ resource: Resource, force: Bool = false) -> Request? {
        if force {
            return resource.load()
        }

        return resource.loadIfNeeded()
    }
}
