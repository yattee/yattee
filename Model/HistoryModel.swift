import CoreData
import CoreMedia
import Defaults
import Foundation
import Siesta
import SwiftyJSON

extension PlayerModel {
    func historyVideo(_ id: String) -> Video? {
        historyVideos.first { $0.videoID == id }
    }

    func loadHistoryVideoDetails(_ watch: Watch, onCompletion: @escaping () -> Void = {}) {
        guard historyVideo(watch.videoID).isNil else {
            onCompletion()
            return
        }

        if !Video.VideoID.isValid(watch.videoID), let url = URL(string: watch.videoID) {
            historyVideos.append(.local(url))
            onCompletion()
            return
        }

        if let video = VideosCacheModel.shared.retrieveVideo(watch.video.cacheKey) {
            historyVideos.append(video)
            onCompletion()
            return
        }

        guard let api = playerAPI(watch.video) else { return }

        api.video(watch.videoID)
            .load()
            .onSuccess { [weak self] response in
                guard let self else { return }

                if let video: Video = response.typedContent() {
                    VideosCacheModel.shared.storeVideo(video)
                    self.historyVideos.append(video)
                    onCompletion()
                }
            }
            .onCompletion { _ in
                self.logger.info("LOADED history details: \(watch.videoID)")
            }
    }

    func updateWatch(finished: Bool = false, time: CMTime? = nil) {
        guard let currentVideo, saveHistory, isPlaying else { return }

        let id = currentVideo.videoID
        let time = time ?? backend.currentTime
        let seconds = time?.seconds ?? 0
        if seconds < 3 {
            return
        }

        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID = %@", id as String)

        let results = try? backgroundContext.fetch(watchFetchRequest)

        backgroundContext.perform { [weak self] in
            guard let self, finished || time != nil || self.backend.isPlaying else {
                return
            }

            let watch: Watch!

            let duration = self.activeBackend == .mpv ? self.playerTime.duration.seconds : self.avPlayerBackend.playerItemDuration?.seconds ?? 0

            if results?.isEmpty ?? true {
                watch = Watch(context: self.backgroundContext)
                watch.videoID = id
                watch.appName = currentVideo.app.rawValue
                watch.instanceURL = currentVideo.instanceURL
            } else {
                watch = results?.first
            }

            if duration.isFinite, duration > 0 {
                watch.videoDuration = duration
            }

            if watch.finished {
                if !finished, self.resetWatchedStatusOnPlaying, seconds.isFinite, seconds > 0 {
                    watch.stoppedAt = seconds
                }
            } else if seconds.isFinite, seconds > 0 {
                watch.stoppedAt = seconds
            }

            watch.watchedAt = Date()

            try? self.backgroundContext.save()
        }
    }

    func removeHistory() {
        removeAllWatches()
        BookmarksCacheModel.shared.clear()
    }

    func removeWatch(_ watch: Watch) {
        context.perform { [weak self] in
            guard let self else { return }
            self.context.delete(watch)

            try? self.context.save()

            FeedModel.shared.calculateUnwatchedFeed()
            WatchModel.shared.watchesChanged()
        }
    }

    func removeAllWatches() {
        let watchesFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Watch")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: watchesFetchRequest)

        do {
            try context.executeAndMergeChanges(deleteRequest)
            try context.save()
        } catch let error as NSError {
            logger.info(.init(stringLiteral: error.localizedDescription))
        }
    }
}
