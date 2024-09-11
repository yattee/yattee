import AVKit
import Defaults
import Foundation
import Siesta
import SwiftUI

extension PlayerModel {
    var currentVideo: Video? {
        currentItem?.video
    }

    var videoForDisplay: Video? {
        videoBeingOpened ?? currentVideo
    }

    func play(_ videos: [Video], shuffling: Bool = false) {
        navigation.presentingChannelSheet = false

        playbackMode = shuffling ? .shuffle : .queue

        videos.forEach { enqueueVideo($0, loadDetails: false) }

        #if os(iOS)
            onPresentPlayer.append { [weak self] in self?.advanceToNextItem() }
        #else
            advanceToNextItem()
        #endif

        show()
    }

    func playNext(_ video: Video) {
        enqueueVideo(video, play: currentItem.isNil, prepending: true)
    }

    func playNow(_ video: Video, at time: CMTime? = nil) {
        navigation.presentingChannelSheet = false

        if playingInPictureInPicture, closePiPOnNavigation {
            closePiP()
        }

        videoBeingOpened = video

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
        navigation.presentingChannelSheet = false

        withAnimation {
            aspectRatio = VideoPlayerView.defaultAspectRatio
            currentItem = item
        }

        if !time.isNil {
            currentItem.playbackTime = time
        } else if currentItem.playbackTime.isNil {
            currentItem.playbackTime = .zero
        }

        preservedTime = currentItem.playbackTime

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let video = item.video else {
                return
            }

            if video.isLocal {
                self.videoBeingOpened = nil
                self.availableStreams = video.streams
                return
            }

            guard let playerInstance = self.playerInstance else { return }
            let streamsInstance = video.streams.compactMap(\.instance).first

            if video.streams.isEmpty || streamsInstance.isNil || streamsInstance!.apiURLString != playerInstance.apiURLString {
                self.loadAvailableStreams(video) { [weak self] _ in
                    self?.videoBeingOpened = nil
                }
            } else {
                self.videoBeingOpened = nil
                self.streamsWithInstance(instance: playerInstance, streams: video.streams) { processedStreams in
                    self.availableStreams = processedStreams
                }
            }
        }
    }

    var playerInstance: Instance? {
        InstancesModel.shared.forPlayer ?? accounts.current?.instance ?? InstancesModel.shared.all.first
    }

    func playerAPI(_ video: Video) -> VideosAPI? {
        guard let url = video.instanceURL else { return accounts.api }
        if accounts.current?.url == url { return accounts.api }
        switch video.app {
        case .local:
            return nil
        case .peerTube:
            return PeerTubeAPI.withAnonymousAccountForInstanceURL(url)
        case .invidious:
            return InvidiousAPI.withAnonymousAccountForInstanceURL(url)
        case .piped:
            return PipedAPI.withAnonymousAccountForInstanceURL(url)
        }
    }

    var qualityProfile: QualityProfile? {
        qualityProfileSelection ?? QualityProfilesModel.shared.automaticProfile
    }

    var streamByQualityProfile: Stream? {
        let profile = qualityProfile ?? .defaultProfile

        // First attempt: Filter by both `canPlay` and `isPreferred`
        if let streamPreferredForProfile = backend.bestPlayable(
            availableStreams.filter { backend.canPlay($0) && profile.isPreferred($0) },
            maxResolution: profile.resolution, formatOrder: profile.formats
        ) {
            return streamPreferredForProfile
        }

        // Fallback: Filter by `canPlay` only
        let fallbackStream = backend.bestPlayable(
            availableStreams.filter { backend.canPlay($0) },
            maxResolution: profile.resolution, formatOrder: profile.formats
        )

        // If no stream is found, trigger the error handler
        guard let finalStream = fallbackStream else {
            let error = RequestError(
                userMessage: "No supported streams available.",
                cause: NSError(domain: "stream.yatte.app", code: -1, userInfo: [NSLocalizedDescriptionKey: "No supported streams available"])
            )
            videoLoadFailureHandler(error, video: currentVideo)
            return nil
        }

        // Return the found stream
        return finalStream
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

        if let nextItem {
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
            return autoplayItem != nil
        }
    }

    func advanceToItem(_ newItem: PlayerQueueItem, at time: CMTime? = nil) {
        prepareCurrentItemForHistory()

        remove(newItem)

        navigation.presentingChannelSheet = false
        currentItem = newItem
        currentItem.playbackTime = time

        let playTime = currentItem.shouldRestartPlaying ? CMTime.zero : time
        guard let video = newItem.video else { return }
        playerAPI(video)?.loadDetails(currentItem, failureHandler: { self.videoLoadFailureHandler($0, video: video) }) { newItem in
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
            guard let self else {
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
            navigation.presentingChannelSheet = false

            withAnimation {
                aspectRatio = VideoPlayerView.defaultAspectRatio
                navigation.presentingChannelSheet = false
                currentItem = item
            }
            videoBeingOpened = video
        }

        if loadDetails {
            playerAPI(item.video)?.loadDetails(item, failureHandler: { self.videoLoadFailureHandler($0, video: video) }) { [weak self] newItem in
                guard let self else { return }
                videoDetailsLoadHandler(newItem.video, newItem)

                if play {
                    self.playItem(newItem)
                } else {
                    self.queue.insert(newItem, at: prepending ? 0 : self.queue.endIndex)
                }
            }
        } else {
            videoDetailsLoadHandler(video, item)
            queue.insert(item, at: prepending ? 0 : queue.endIndex)
        }

        return item
    }

    func prepareCurrentItemForHistory(finished: Bool = false) {
        if let currentItem {
            if Defaults[.saveHistory] {
                if let video = currentVideo, !historyVideos.contains(where: { $0 == video }) {
                    historyVideos.append(video)
                }
                updateWatch(finished: finished, time: backend.currentTime)
            }

            if let video = currentItem.video,
               video.isLocal,
               video.localStreamIsFile,
               let localURL = video.localStream?.localURL
            {
                logger.info("stopping security scoped resource access for \(localURL)")
                localURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    func playHistory(_ item: PlayerQueueItem, at time: CMTime? = nil) {
        guard let video = item.video else { return }

        var time = time ?? item.playbackTime

        if item.shouldRestartPlaying {
            time = .zero
        }

        let newItem = enqueueVideo(video, atTime: time, prepending: true)

        advanceToItem(newItem!, at: time)
    }

    func removeQueueItems() {
        queue.removeAll()
    }

    func restoreQueue() {
        var restoredQueue = [PlayerQueueItem?]()

        if let lastPlayed,
           !Defaults[.queue].contains(where: { $0.videoID == lastPlayed.videoID })
        {
            restoredQueue.append(lastPlayed)
            self.lastPlayed = nil
        }

        restoredQueue.append(contentsOf: Defaults[.queue])
        queue = restoredQueue.compactMap { $0 }
        queue.forEach { loadQueueVideoDetails($0) }
    }

    func loadQueueVideoDetails(_ item: PlayerQueueItem) {
        guard !accounts.current.isNil, !item.hasDetailsLoaded else { return }

        let videoID = item.video?.videoID ?? item.videoID

        let video = item.video ?? Video(app: item.app ?? .local, instanceURL: item.instanceURL, videoID: videoID)

        let replaceQueueItem: (PlayerQueueItem) -> Void = { newItem in
            self.queue.filter { $0.videoID == videoID }.forEach { item in
                if let index = self.queue.firstIndex(of: item) {
                    self.queue[index] = newItem
                }
            }
        }

        if let video = VideosCacheModel.shared.retrieveVideo(video.cacheKey) {
            var item = item
            item.id = UUID()
            item.video = video
            replaceQueueItem(item)
            return
        }

        playerAPI(video)?
            .loadDetails(item, failureHandler: nil) { [weak self] newItem in
                guard let self else { return }

                replaceQueueItem(newItem)

                self.logger.info("LOADED queue details: \(videoID)")
            }
    }

    private func videoLoadFailureHandler(_ error: RequestError, video: Video? = nil) {
        guard let video else {
            presentErrorAlert(error)
            return
        }

        let videoID = video.videoID
        let currentRetry = retryAttempts[videoID] ?? 0

        if currentRetry < Defaults[.videoLoadingRetryCount] {
            retryAttempts[videoID] = currentRetry + 1

            logger.info("Retry attempt \(currentRetry + 1) for video \(videoID) due to error: \(error)")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.enqueueVideo(video, play: true, prepending: true, loadDetails: true)
            }
            return
        }

        retryAttempts[videoID] = 0
        presentErrorAlert(error, video: video)
    }

    private func presentErrorAlert(_ error: RequestError, video: Video? = nil) {
        var message = error.userMessage
        if let errorDictionary = error.json.dictionaryObject,
           let errorMessage = errorDictionary["message"] ?? errorDictionary["error"],
           let errorString = errorMessage as? String
        {
            message += "\n"
            message += errorString
        }

        var retryButton: Alert.Button?

        if let video {
            retryButton = Alert.Button.default(Text("Retry")) { [weak self] in
                if let self {
                    self.enqueueVideo(video, play: true, prepending: true, loadDetails: true)
                }
            }
        }

        var alert: Alert
        if let retryButton {
            alert = Alert(
                title: Text("Could not load video"),
                message: Text(message),
                primaryButton: .cancel { [weak self] in
                    guard let self else { return }
                    self.closeCurrentItem()
                },
                secondaryButton: retryButton
            )
        } else {
            alert = Alert(title: Text("Could not load video"))
        }

        navigation.presentAlert(alert)
    }
}
