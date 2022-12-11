import Foundation
import Siesta

final class FeedModel: ObservableObject {
    static let shared = FeedModel()

    @Published var isLoading = false
    @Published var videos = [Video]()
    @Published private var page = 1

    private var accounts = AccountsModel.shared

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
                            FeedCacheModel.shared.storeFeed(account: account, videos: self.videos)
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

    var feedTime: Date? {
        if let account = accounts.current {
            return FeedCacheModel.shared.getFeedTime(account: account)
        }

        return nil
    }

    var formattedFeedTime: String {
        if let feedTime {
            let isSameDay = Calendar(identifier: .iso8601).isDate(feedTime, inSameDayAs: Date())
            let formatter = isSameDay ? CacheModel.shared.dateFormatterForTimeOnly : CacheModel.shared.dateFormatter
            return formatter.string(from: feedTime)
        }

        return ""
    }

    private func loadCachedFeed() {
        guard let account = accounts.current else { return }
        let cache = FeedCacheModel.shared.retrieveFeed(account: account)
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
