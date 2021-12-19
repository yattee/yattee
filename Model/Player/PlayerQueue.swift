import AVFoundation
import Defaults
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
        player.replaceCurrentItem(with: nil)
        addCurrentItemToHistory()

        enqueueVideo(video, prepending: true) { _, item in
            self.advanceToItem(item, at: time)
        }
    }

    func playItem(_ item: PlayerQueueItem, video: Video? = nil, at time: TimeInterval? = nil) {
        comments.reset()
        currentItem = item

        if !time.isNil {
            currentItem.playbackTime = .secondsInDefaultTimescale(time!)
        } else if currentItem.playbackTime.isNil {
            currentItem.playbackTime = .zero
        }

        if video != nil {
            currentItem.video = video!
        }

        preservedTime = currentItem.playbackTime
        restoreLoadedChannel()

        loadAvailableStreams(currentVideo!)
    }

    func preferredStream(_ streams: [Stream]) -> Stream? {
        let quality = Defaults[.quality]
        var streams = streams

        if let id = Defaults[.playerInstanceID] {
            streams = streams.filter { $0.instance.id == id }
        }

        switch quality {
        case .best:
            return streams.first { $0.kind == .hls } ?? streams.first
        default:
            let sorted = streams.filter { $0.kind != .hls }.sorted { $0.resolution > $1.resolution }
            return sorted.first(where: { $0.resolution.height <= quality.value.height })
        }
    }

    func advanceToNextItem() {
        addCurrentItemToHistory()

        if let nextItem = queue.first {
            advanceToItem(nextItem)
        }
    }

    func advanceToItem(_ newItem: PlayerQueueItem, at time: TimeInterval? = nil) {
        player.replaceCurrentItem(with: nil)
        addCurrentItemToHistory()

        remove(newItem)

        accounts.api.loadDetails(newItem) { newItem in
            self.playItem(newItem, video: newItem.video, at: time)
        }
    }

    @discardableResult func remove(_ item: PlayerQueueItem) -> PlayerQueueItem? {
        if let index = queue.firstIndex(where: { $0.videoID == item.videoID }) {
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
        player.currentItem == item && (presentingPlayer || playerNavigationLinkActive || playingInPictureInPicture)
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
        if let item = currentItem, Defaults[.saveHistory] {
            addItemToHistory(item)
        }
    }

    func addItemToHistory(_ item: PlayerQueueItem) {
        if let index = history.firstIndex(where: { $0.video?.videoID == item.video?.videoID }) {
            history.remove(at: index)
        }

        history.insert(currentItem, at: 0)
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

    func loadHistoryDetails() {
        guard !accounts.current.isNil else {
            return
        }

        queue = Defaults[.queue]
        queue.forEach { item in
            accounts.api.loadDetails(item) { newItem in
                if let index = self.queue.firstIndex(where: { $0.id == item.id }) {
                    self.queue[index] = newItem
                }
            }
        }

        var savedHistory = Defaults[.history]

        if let lastPlayed = Defaults[.lastPlayed] {
            if let index = savedHistory.firstIndex(where: { $0.videoID == lastPlayed.videoID }) {
                var updatedLastPlayed = savedHistory[index]

                updatedLastPlayed.playbackTime = lastPlayed.playbackTime
                updatedLastPlayed.videoDuration = lastPlayed.videoDuration

                savedHistory.remove(at: index)
                savedHistory.insert(updatedLastPlayed, at: 0)
            } else {
                savedHistory.insert(lastPlayed, at: 0)
            }

            Defaults[.lastPlayed] = nil
        }

        history = savedHistory
        history.forEach { item in
            accounts.api.loadDetails(item) { newItem in
                if let index = self.history.firstIndex(where: { $0.id == item.id }) {
                    self.history[index] = newItem
                }
            }
        }
    }
}
