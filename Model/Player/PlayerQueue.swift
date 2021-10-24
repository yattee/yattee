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

    func playNow(_ video: Video, at time: TimeInterval? = nil) {
        addCurrentItemToHistory()

        enqueueVideo(video, prepending: true) { _, item in
            self.advanceToItem(item, at: time)
        }
    }

    func playItem(_ item: PlayerQueueItem, video: Video? = nil, at time: TimeInterval? = nil) {
        currentItem = item

        if !time.isNil {
            currentItem.playbackTime = .secondsInDefaultTimescale(time!)
        } else if currentItem.playbackTime.isNil {
            currentItem.playbackTime = .zero
        }

        if video != nil {
            currentItem.video = video!
        }

        savedTime = currentItem.playbackTime

        loadAvailableStreams(currentVideo!) { streams in
            guard let stream = streams.first else {
                return
            }

            self.streamSelection = stream
            self.playStream(
                stream,
                of: self.currentVideo!,
                preservingTime: !self.currentItem.playbackTime.isNil
            )
        }
    }

    func advanceToNextItem() {
        addCurrentItemToHistory()

        if let nextItem = queue.first {
            advanceToItem(nextItem)
        }
    }

    func advanceToItem(_ newItem: PlayerQueueItem, at time: TimeInterval? = nil) {
        addCurrentItemToHistory()

        remove(newItem)

        accounts.api.loadDetails(newItem) { newItem in
            self.playItem(newItem, video: newItem.video, at: time)
        }
    }

    @discardableResult func remove(_ item: PlayerQueueItem) -> PlayerQueueItem? {
        if let index = queue.firstIndex(where: { $0 == item }) {
            return queue.remove(at: index)
        }

        return nil
    }

    func resetQueue() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                return
            }

            self.currentItem = nil
            self.stream = nil
            self.removeQueueItems()
        }

        player.replaceCurrentItem(with: nil)
    }

    func isAutoplaying(_ item: AVPlayerItem) -> Bool {
        guard player.currentItem == item else {
            return false
        }

        if !autoPlayItems {
            autoPlayItems = true
            return false
        }

        return true
    }

    @discardableResult func enqueueVideo(
        _ video: Video,
        play: Bool = false,
        atTime: CMTime? = nil,
        prepending: Bool = false,
        videoDetailsLoadHandler: @escaping (Video, PlayerQueueItem) -> Void = { _, _ in }
    ) -> PlayerQueueItem? {
        let item = PlayerQueueItem(video, playbackTime: atTime)

        queue.insert(item, at: prepending ? 0 : queue.endIndex)

        accounts.api.loadDetails(item) { newItem in
            videoDetailsLoadHandler(newItem.video, newItem)

            if play {
                self.playItem(newItem, video: video)
            }
        }

        return item
    }

    func addCurrentItemToHistory() {
        if let item = currentItem {
            if let index = history.firstIndex(where: { $0.video.videoID == item.video?.videoID }) {
                history.remove(at: index)
            }

            history.insert(currentItem, at: 0)
        }
    }

    func playHistory(_ item: PlayerQueueItem) {
        var time = item.playbackTime

        if item.shouldRestartPlaying {
            time = .zero
        }

        let newItem = enqueueVideo(item.video, atTime: time, prepending: true)

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
