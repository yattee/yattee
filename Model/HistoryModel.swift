import CoreData
import CoreMedia
import Defaults
import Foundation

extension PlayerModel {
    func historyVideo(_ id: String) -> Video? {
        historyVideos.first { $0.videoID == id }
    }

    func loadHistoryVideoDetails(_ id: Video.ID) {
        guard historyVideo(id).isNil else {
            return
        }

        accounts.api.video(id).load().onSuccess { [weak self] response in
            guard let video: Video = response.typedContent() else {
                return
            }

            self?.historyVideos.append(video)
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

        let watch: Watch!
        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID = %@", id as String)

        let results = try? context.fetch(watchFetchRequest)

        if results?.isEmpty ?? true {
            if seconds < 1 {
                return
            }
            watch = Watch(context: context)
            watch.videoID = id
        } else {
            watch = results?.first

            if !Defaults[.resetWatchedStatusOnPlaying], watch.finished {
                return
            }
        }

        if let seconds = playerItemDuration?.seconds {
            watch.videoDuration = seconds
        }

        if finished {
            watch.stoppedAt = watch.videoDuration
        } else if seconds.isFinite, seconds > 0 {
            watch.stoppedAt = seconds
        }

        watch.watchedAt = Date()

        try? context.save()
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
