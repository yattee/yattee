import AVKit
import Defaults
import Foundation
import Siesta

extension PlayerModel {
    var currentVideo: Video? {
        currentItem?.video
    }

    func play(_ videos: [Video], shuffling: Bool = false, inNavigationView: Bool = false) {
        let videosToPlay = shuffling ? videos.shuffled() : videos

        guard let first = videosToPlay.first else {
            return
        }

        enqueueVideo(first, prepending: true) { _, item in
            self.advanceToItem(item)
        }

        videosToPlay.dropFirst().reversed().forEach { video in
            enqueueVideo(video, prepending: true) { _, item in
                if item.video == first {
                    self.advanceToItem(item)
                }
            }
        }

        if inNavigationView {
            playerNavigationLinkActive = true
        } else {
            show()
        }
    }

    func playNext(_ video: Video) {
        enqueueVideo(video, prepending: true) { _, item in
            if self.currentItem.isNil {
                self.advanceToItem(item)
            }
        }
    }

    func playNow(_ video: Video, at time: CMTime? = nil) {
        if playingInPictureInPicture, closePiPOnNavigation {
            closePiP()
        }

        prepareCurrentItemForHistory()

        enqueueVideo(video, prepending: true) { _, item in
            self.advanceToItem(item, at: time)
        }
    }

    func playItem(_ item: PlayerQueueItem, video: Video? = nil, at time: CMTime? = nil) {
        if !playingInPictureInPicture {
            backend.closeItem()
        }

        comments.reset()
        stream = nil
        currentItem = item

        if !time.isNil {
            currentItem.playbackTime = time
        } else if currentItem.playbackTime.isNil {
            currentItem.playbackTime = .zero
        }

        if video != nil {
            currentItem.video = video!
        }

        preservedTime = currentItem.playbackTime

        DispatchQueue.main.async { [weak self] in
            guard let video = self?.currentVideo else {
                return
            }

            self?.loadAvailableStreams(video)
        }
    }

    func preferredStream(_ streams: [Stream]) -> Stream? {
        let quality = Defaults[.quality]
        var streams = streams

        if let id = Defaults[.playerInstanceID] {
            streams = streams.filter { $0.instance.id == id }
        }

        streams = streams.filter { backend.canPlay($0) }

        return backend.bestPlayable(streams, maxResolution: quality)
    }

    func advanceToNextItem() {
        prepareCurrentItemForHistory()

        if let nextItem = queue.first {
            advanceToItem(nextItem)
        }
    }

    func advanceToItem(_ newItem: PlayerQueueItem, at time: CMTime? = nil) {
        prepareCurrentItemForHistory()

        remove(newItem)

        currentItem = newItem
        pause()

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

        backend.closeItem()
    }

    @discardableResult func enqueueVideo(
        _ video: Video,
        play: Bool = false,
        atTime: CMTime? = nil,
        prepending: Bool = false,
        videoDetailsLoadHandler: @escaping (Video, PlayerQueueItem) -> Void = { _, _ in }
    ) -> PlayerQueueItem? {
        let item = PlayerQueueItem(video, playbackTime: atTime)

        if play {
            currentItem = item
            // pause playing current video as it's going to be replaced with next one
            pause()
        }

        queue.insert(item, at: prepending ? 0 : queue.endIndex)

        accounts.api.loadDetails(item) { newItem in
            videoDetailsLoadHandler(newItem.video, newItem)

            if play {
                self.playItem(newItem, video: video)
            }
        }

        return item
    }

    func prepareCurrentItemForHistory(finished: Bool = false) {
        if !currentItem.isNil, Defaults[.saveHistory] {
            if let video = currentVideo, !historyVideos.contains(where: { $0 == video }) {
                historyVideos.append(video)
            }
            updateWatch(finished: finished)
        }
    }

    func playHistory(_ item: PlayerQueueItem, at time: CMTime? = nil) {
        var time = time ?? item.playbackTime

        if item.shouldRestartPlaying {
            time = .zero
        }

        let newItem = enqueueVideo(item.video, atTime: time, prepending: true)

        advanceToItem(newItem!)
    }

    func removeQueueItems() {
        queue.removeAll()
    }

    func restoreQueue() {
        guard !accounts.current.isNil else {
            return
        }

        var restoredQueue = [PlayerQueueItem?]()

        if let lastPlayed = Defaults[.lastPlayed],
           !Defaults[.queue].contains(where: { $0.videoID == lastPlayed.videoID })
        {
            restoredQueue.append(lastPlayed)
            Defaults[.lastPlayed] = nil
        }

        restoredQueue.append(contentsOf: Defaults[.queue])
        queue = restoredQueue.compactMap { $0 }

        queue.forEach { item in
            accounts.api.loadDetails(item) { newItem in
                if let index = self.queue.firstIndex(where: { $0.id == item.id }) {
                    self.queue[index] = newItem
                }
            }
        }
    }
}
