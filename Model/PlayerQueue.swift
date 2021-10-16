import AVFoundation
import Foundation
import Siesta

extension PlayerModel {
    var currentVideo: Video? {
        currentItem?.video
    }

    func playAll(_ videos: [Video]) {
        let first = videos.first

        videos.forEach { video in
            enqueueVideo(video) { _, item in
                if item.video == first {
                    self.advanceToItem(item)
                }
            }
        }
    }

    func playNext(_ video: Video) {
        enqueueVideo(video, prepending: true) { _, item in
            if self.currentItem.isNil {
                self.advanceToItem(item)
            }
        }
    }

    func playNow(_ video: Video) {
        addCurrentItemToHistory()

        enqueueVideo(video, prepending: true) { _, item in
            self.advanceToItem(item)
        }
    }

    func playItem(_ item: PlayerQueueItem, video: Video? = nil) {
        currentItem = item

        if video != nil {
            currentItem.video = video!
        }

        playVideo(currentItem.video)
    }

    func advanceToNextItem() {
        addCurrentItemToHistory()

        if let nextItem = queue.first {
            advanceToItem(nextItem)
        }
    }

    func advanceToItem(_ newItem: PlayerQueueItem) {
        let item = remove(newItem)!
        loadDetails(newItem.video) { video in
            self.playItem(item, video: video)
        }
    }

    @discardableResult func remove(_ item: PlayerQueueItem) -> PlayerQueueItem? {
        if let index = queue.firstIndex(where: { $0 == item }) {
            return queue.remove(at: index)
        }

        return nil
    }

    func resetQueue() {
        DispatchQueue.main.async {
            self.currentItem = nil
            self.stream = nil
            self.removeQueueItems()
            self.timeObserver = nil
        }

        player.replaceCurrentItem(with: nil)
    }

    func isAutoplaying(_ item: AVPlayerItem) -> Bool {
        player.currentItem == item
    }

    @discardableResult func enqueueVideo(
        _ video: Video,
        play: Bool = false,
        prepending: Bool = false,
        videoDetailsLoadHandler: @escaping (Video, PlayerQueueItem) -> Void = { _, _ in }
    ) -> PlayerQueueItem? {
        let item = PlayerQueueItem(video)

        queue.insert(item, at: prepending ? 0 : queue.endIndex)

        loadDetails(video) { video in
            videoDetailsLoadHandler(video, item)

            if play {
                self.playItem(item, video: video)
            }
        }

        return item
    }

    func videoResource(_ id: Video.ID) -> Resource {
        accounts.invidious.video(id)
    }

    private func loadDetails(_ video: Video?, onSuccess: @escaping (Video) -> Void) {
        guard video != nil else {
            return
        }

        if !video!.streams.isEmpty {
            logger.critical("not loading video details again")
            onSuccess(video!)
            return
        }

        videoResource(video!.videoID).load().onSuccess { response in
            if let video: Video = response.typedContent() {
                onSuccess(video)
            }
        }
    }

    func addCurrentItemToHistory() {
        if let item = currentItem, !history.contains(where: { $0.video.videoID == item.video.videoID }) {
            history.insert(item, at: 0)
        }
    }

    func playHistory(_ item: PlayerQueueItem) {
        let newItem = enqueueVideo(item.video, prepending: true)

        advanceToItem(newItem!)

        if let historyItemIndex = history.firstIndex(of: item) {
            history.remove(at: historyItemIndex)
        }
    }

    @discardableResult func removeHistory(_ item: PlayerQueueItem) -> PlayerQueueItem? {
        if let index = history.firstIndex(where: { $0 == item }) {
            return history.remove(at: index)
        }

        return nil
    }

    func removeQueueItems() {
        queue.removeAll()
    }

    func removeHistoryItems() {
        history.removeAll()
    }
}
