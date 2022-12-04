import CoreData
import CoreMedia
import Defaults
import Foundation
import SwiftyJSON

extension PlayerModel {
    func historyVideo(_ id: String) -> Video? {
        historyVideos.first { $0.videoID == id }
    }

    func loadHistoryVideoDetails(_ id: Video.ID) {
        guard historyVideo(id).isNil else {
            return
        }

        if !Video.VideoID.isValid(id), let url = URL(string: id) {
            historyVideos.append(.local(url))
            return
        }

        playerAPI.video(id)
            .load()
            .onSuccess { [weak self] response in
                guard let self else { return }

                if let video: Video = response.typedContent() {
                    self.historyVideos.append(video)
                }
            }
            .onCompletion { _ in
                self.logger.info("LOADED history details: \(id)")

                if self.historyItemBeingLoaded == id {
                    self.logger.info("setting no history loaded")
                    self.historyItemBeingLoaded = nil
                }

                if let id = self.historyItemsToLoad.popLast() {
                    self.loadHistoryVideoDetails(id)
                }
            }
    }

    func updateWatch(finished: Bool = false) {
        guard let id = currentVideo?.videoID,
              Defaults[.saveHistory]
        else {
            return
        }

        let time = backend.currentTime
        let seconds = time?.seconds ?? 0

        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID = %@", id as String)

        let results = try? backgroundContext.fetch(watchFetchRequest)

        backgroundContext.perform { [weak self] in
            guard let self, finished || self.backend.isPlaying else {
                return
            }

            let watch: Watch!

            if results?.isEmpty ?? true {
                if seconds < 1 {
                    return
                }
                watch = Watch(context: self.backgroundContext)
                watch.videoID = id
            } else {
                watch = results?.first
            }

            let duration = self.playerTime.duration.seconds
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
        CacheModel.shared.removeAll()
    }

    func removeWatch(_ watch: Watch) {
        context.delete(watch)
        try? context.save()
    }

    func removeAllWatches() {
        let watchesFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Watch")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: watchesFetchRequest)
        _ = try? context.execute(deleteRequest)
        _ = try? context.save()
    }
}
