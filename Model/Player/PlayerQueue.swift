import AVKit
import Defaults
import Foundation
import Siesta

extension PlayerModel {
    var currentVideo: Video? {
        currentItem?.video
    }

    func play(_ videos: [Video]) {
        videos.forEach { enqueueVideo($0, loadDetails: false) }

        #if os(iOS)
            onPresentPlayer = { [weak self] in self?.advanceToNextItem() }
        #else
            advanceToNextItem()
        #endif

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
        advancing = false

        if !playingInPictureInPicture, !currentItem.isNil {
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
            guard let self = self else { return }
            guard let video = self.currentVideo else {
                return
            }

            self.videoBeingOpened = nil

            guard let playerInstance = self.playerInstance else { return }
            let streamsInstance = video.streams.compactMap(\.instance).first

            if video.streams.isEmpty || streamsInstance != playerInstance {
                self.loadAvailableStreams(video)
            } else {
                self.availableStreams = self.streamsWithInstance(instance: playerInstance, streams: video.streams)
            }
        }
    }

    var playerInstance: Instance? {
        InstancesModel.forPlayer ?? accounts.current?.instance ?? InstancesModel.all.first
    }

    var playerAPI: VideosAPI {
        playerInstance?.anonymous ?? accounts.api
    }

    var qualityProfile: QualityProfile? {
        qualityProfileSelection ?? QualityProfilesModel.shared.automaticProfile
    }

    var streamByQualityProfile: Stream? {
        let profile = qualityProfile ?? .defaultProfile

        if let streamPreferredForProfile = backend.bestPlayable(
            availableStreams.filter { backend.canPlay($0) && profile.isPreferred($0) },
            maxResolution: profile.resolution
        ) {
            return streamPreferredForProfile
        }

        return backend.bestPlayable(availableStreams.filter { backend.canPlay($0) }, maxResolution: profile.resolution)
    }

    func advanceToNextItem() {
        guard !advancing else {
            return
        }
        advancing = true
        prepareCurrentItemForHistory()

        var nextItem: PlayerQueueItem?
        switch playbackMode {
        case .queue:
            nextItem = queue.first
        case .shuffle:
            nextItem = queue.randomElement()
        case .related:
            nextItem = autoplayItem
        case .loopOne:
            nextItem = nil
        }

        resetAutoplay()

        if let nextItem = nextItem {
            advanceToItem(nextItem)
        } else {
            advancing = false
        }
    }

    var isAdvanceToNextItemAvailable: Bool {
        switch playbackMode {
        case .loopOne:
            return false
        case .queue, .shuffle:
            return !queue.isEmpty
        case .related:
            return !autoplayItem.isNil
        }
    }

    func advanceToItem(_ newItem: PlayerQueueItem, at time: CMTime? = nil) {
        prepareCurrentItemForHistory()

        remove(newItem)

        currentItem = newItem
        currentItem.playbackTime = time

        let playTime = currentItem.shouldRestartPlaying ? CMTime.zero : time
        playerAPI.loadDetails(currentItem, failureHandler: videoLoadFailureHandler) { newItem in
            self.playItem(newItem, at: playTime)
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
            playerAPI.loadDetails(item, failureHandler: videoLoadFailureHandler) { [weak self] newItem in
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
        guard let video = item.video else { return }

        var time = time ?? item.playbackTime

        if item.shouldRestartPlaying {
            time = .zero
        }

        let newItem = enqueueVideo(video, atTime: time, prepending: true)

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

        playerAPI.loadDetails(item, completionHandler: { newItem in
            if let index = self.queue.firstIndex(where: { $0.id == item.id }) {
                self.queue[index] = newItem
            }
        })
    }

    private func videoLoadFailureHandler(_ error: RequestError) {
        var message = error.userMessage
        if let errorDictionary = error.json.dictionaryObject,
           let errorMessage = errorDictionary["message"] ?? errorDictionary["error"],
           let errorString = errorMessage as? String
        {
            message += "\n"
            message += errorString
        }

        navigation.presentAlert(title: "Could not load video", message: message)
        advancing = false
        videoBeingOpened = nil
        currentItem = nil
    }
}
