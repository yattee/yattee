import Cache
import CoreData
import Defaults
import Foundation
import Siesta
import SwiftyJSON

final class FeedModel: ObservableObject, CacheModel {
    static let shared = FeedModel()

    @Published var isLoading = false
    @Published var videos = [Video]()
    @Published private var page = 1
    @Published var watchedUUID = UUID()

    private var feedCount = UnwatchedFeedCountModel.shared
    private var cacheModel = FeedCacheModel.shared
    private var accounts = AccountsModel.shared

    var storage: Storage<String, JSON>?

    @Published var error: RequestError?

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
                    self.error = nil
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
                .onFailure { self.error = $0 }
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

    func onAccountChange() {
        reset()
        error = nil
        loadResources(force: true)
        calculateUnwatchedFeed()
    }

    func calculateUnwatchedFeed() {
        guard let account = accounts.current, accounts.signedIn else { return }
        let feed = cacheModel.retrieveFeed(account: account)
        backgroundContext.perform { [weak self] in
            guard let self else { return }

            let watched = self.watchFetchRequestResult(feed, context: self.backgroundContext).filter(\.finished)
            let unwatched = feed.filter { video in !watched.contains { $0.videoID == video.videoID } }
            let unwatchedCount = max(0, feed.count - watched.count)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if unwatchedCount != self.feedCount.unwatched[account] {
                    self.feedCount.unwatched[account] = unwatchedCount
                }

                let byChannel = Dictionary(grouping: unwatched) { $0.channel.id }.mapValues(\.count)
                self.feedCount.unwatchedByChannel[account] = byChannel
                self.watchedUUID = UUID()
            }
        }
    }

    func markAllFeedAsWatched() {
        let mark = { [weak self] in
            guard let self else { return }
            self.markVideos(self.videos, watched: true, watchedAt: Date(timeIntervalSince1970: 0))
        }

        if videos.isEmpty {
            loadCachedFeed { mark() }
        } else {
            mark()
        }
    }

    var canMarkAllFeedAsWatched: Bool {
        guard let account = accounts.current, accounts.signedIn else { return false }
        return (feedCount.unwatched[account] ?? 0) > 0
    }

    func canMarkChannelAsWatched(_ channelID: Channel.ID) -> Bool {
        guard let account = accounts.current, accounts.signedIn else { return false }

        return feedCount.unwatchedByChannel[account]?.keys.contains(channelID) ?? false
    }

    func markChannelAsWatched(_ channelID: Channel.ID) {
        guard accounts.signedIn else { return }

        let mark = { [weak self] in
            guard let self else { return }
            self.markVideos(self.videos.filter { $0.channel.id == channelID }, watched: true)
        }

        if videos.isEmpty {
            loadCachedFeed { mark() }
        } else {
            mark()
        }
    }

    func markChannelAsUnwatched(_ channelID: Channel.ID) {
        guard accounts.signedIn else { return }

        let mark = { [weak self] in
            guard let self else { return }
            self.markVideos(self.videos.filter { $0.channel.id == channelID }, watched: false)
        }

        if videos.isEmpty {
            loadCachedFeed { mark() }
        } else {
            mark()
        }
    }

    func markAllFeedAsUnwatched() {
        guard accounts.current != nil else { return }

        let mark = { [weak self] in
            guard let self else { return }
            self.markVideos(self.videos, watched: false)
        }

        if videos.isEmpty {
            loadCachedFeed { mark() }
        } else {
            mark()
        }
    }

    func markVideos(_ videos: [Video], watched: Bool, watchedAt: Date? = nil) {
        guard accounts.signedIn, let account = accounts.current else { return }

        backgroundContext.perform { [weak self] in
            guard let self else { return }

            if watched {
                videos.forEach { Watch.markAsWatched(videoID: $0.videoID, account: account, duration: $0.length, watchedAt: watchedAt, context: self.backgroundContext) }
            } else {
                let watches = self.watchFetchRequestResult(videos, context: self.backgroundContext)
                watches.forEach { self.backgroundContext.delete($0) }
            }

            try? self.backgroundContext.save()

            self.calculateUnwatchedFeed()
            WatchModel.shared.watchesChanged()
        }
    }

    func playUnwatchedFeed() {
        guard let account = accounts.current, accounts.signedIn else { return }
        let videos = cacheModel.retrieveFeed(account: account)
        guard !videos.isEmpty else { return }

        let watches = watchFetchRequestResult(videos, context: backgroundContext)
        let watchesIDs = watches.map(\.videoID)
        let unwatched = videos.filter { video in
            if Defaults[.hideShorts], video.short {
                return false
            }

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

    var canPlayUnwatchedFeed: Bool {
        guard let account = accounts.current, accounts.signedIn else { return false }
        return (feedCount.unwatched[account] ?? 0) > 0
    }

    var watchedId: String {
        watchedUUID.uuidString
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

    private func loadCachedFeed(_ onCompletion: @escaping () -> Void = {}) {
        guard let account = accounts.current, accounts.signedIn else { return }
        let cache = cacheModel.retrieveFeed(account: account)
        if !cache.isEmpty {
            DispatchQueue.main.async(qos: .userInteractive) { [weak self] in
                self?.videos = cache
                onCompletion()
            }
        }
    }

    private func request(_ resource: Resource, force: Bool = false) -> Request? {
        if force {
            return resource.load()
        }

        return resource.loadIfNeeded()
    }

    private func watchFetchRequestResult(_ videos: [Video], context: NSManagedObjectContext) -> [Watch] {
        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID IN %@", videos.map(\.videoID) as [String])
        return (try? context.fetch(watchFetchRequest)) ?? []
    }
}
