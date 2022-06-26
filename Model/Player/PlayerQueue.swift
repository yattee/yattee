import AVKit
import Defaults
import Foundation
import Siesta

extension PlayerModel {
    var currentVideo: Video? {
        currentItem?.video
    }

    func play(_ videos: [Video], shuffling: Bool = false) {
        let videosToPlay = shuffling ? videos.shuffled() : videos

        guard let first = videosToPlay.first else {
            return
        }

        enqueueVideo(first, prepending: true) { _, item in
            self.advanceToItem(item)
        }

        videosToPlay.dropFirst().reversed().forEach { video in
            enqueueVideo(video, prepending: true, loadDetails: false)
        }

        show()
    }

    func playNext(_ video: Video) {
        enqueueVideo(video, play: currentItem.isNil, prepending: true)
    }

    func playNow(_ video: Video, at time: CMTime? = nil) {
        if playingInPictureInPicture, closePiPOnNavigation {
            closePiP()
        }

        prepareCurrentItemForHistory()

        enqueueVideo(video, play: true, atTime: time, prepending: true) { _, item in
            self.advanceToItem(item, at: time)
        }
    }

    func playItem(_ item: PlayerQueueItem, at time: CMTime? = nil) {
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

        preservedTime = currentItem.playbackTime

        DispatchQueue.main.async { [weak self] in
            guard let video = self?.currentVideo else {
                return
            }
            self?.videoBeingOpened = nil

            if video.streams.isEmpty {
                self?.loadAvailableStreams(video)
            } else {
                guard let instance = self?.accounts.current?.instance ?? InstancesModel.forPlayer ?? InstancesModel.all.first else { return }
                self?.availableStreams = self?.streamsWithInstance(instance: instance, streams: video.streams) ?? video.streams
            }
        }
    }

    func preferredStream(_ streams: [Stream]) -> Stream? {
        backend.bestPlayable(streams.filter { backend.canPlay($0) }, maxResolution: Defaults[.quality])
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

        accounts.api.loadDetails(newItem) { newItem in
            self.playItem(newItem, at: time)
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
        loadDetails: Bool = true,
        videoDetailsLoadHandler: @escaping (Video, PlayerQueueItem) -> Void = { _, _ in }
    ) -> PlayerQueueItem? {
        let item = PlayerQueueItem(video, playbackTime: atTime)

        if play {
            currentItem = item
            videoBeingOpened = video
        }

        if loadDetails {
            accounts.api.loadDetails(item) { [weak self] newItem in
                guard let self = self else { return }
                videoDetailsLoadHandler(newItem.video, newItem)

                if play {
                    self.playItem(newItem)
                } else {
                    self.queue.insert(newItem, at: prepending ? 0 : self.queue.endIndex)
                }
            }
        } else {
            queue.insert(item, at: prepending ? 0 : queue.endIndex)
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
        var restoredQueue = [PlayerQueueItem?]()

        if let lastPlayed = Defaults[.lastPlayed],
           !Defaults[.queue].contains(where: { $0.videoID == lastPlayed.videoID })
        {
            restoredQueue.append(lastPlayed)
            Defaults[.lastPlayed] = nil
        }

        restoredQueue.append(contentsOf: Defaults[.queue])
        queue = restoredQueue.compactMap { $0 }
    }

    func loadQueueVideoDetails(_ item: PlayerQueueItem) {
        guard !accounts.current.isNil, !item.hasDetailsLoaded else { return }

        accounts.api.loadDetails(item) { newItem in
            if let index = self.queue.firstIndex(where: { $0.id == item.id }) {
                self.queue[index] = newItem
            }
        }
    }
}
