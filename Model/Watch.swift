import CoreData
import CoreMedia
import Defaults
import Foundation

@objc(Watch)
final class Watch: NSManagedObject, Identifiable {
    @Default(.watchedThreshold) private var watchedThreshold
    @Default(.saveHistory) private var saveHistory
    @Default(.showWatchingProgress) private var showWatchingProgress
}

extension Watch {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Watch> {
        NSFetchRequest<Watch>(entityName: "Watch")
    }

    @nonobjc class func markAsWatched(videoID: String, account: Account, duration: Double, watchedAt: Date? = nil, context: NSManagedObjectContext) {
        let watchFetchRequest = Watch.fetchRequest()
        watchFetchRequest.predicate = NSPredicate(format: "videoID = %@", videoID as String)

        let results = try? context.fetch(watchFetchRequest)

        context.perform {
            let watch: Watch?

            if results?.isEmpty ?? true {
                watch = Watch(context: context)
                watch?.videoID = videoID
                watch?.appName = account.app?.rawValue
                watch?.instanceURL = account.url
            } else {
                watch = results?.first
            }

            guard let watch else { return }

            watch.videoDuration = duration
            watch.stoppedAt = duration
            watch.watchedAt = watchedAt ?? .init()

            try? context.save()
        }
    }

    @NSManaged var videoID: String
    @NSManaged var videoDuration: Double

    @NSManaged var watchedAt: Date?
    @NSManaged var stoppedAt: Double

    @NSManaged var appName: String?
    @NSManaged var instanceURL: URL?

    var app: VideosApp? {
        guard let appName else { return nil }
        return .init(rawValue: appName)
    }

    var progress: Double {
        guard videoDuration.isFinite, !videoDuration.isZero else {
            return 100
        }

        let progress = (stoppedAt / videoDuration) * 100

        if progress >= Double(watchedThreshold) {
            return 100
        }

        return min(max(progress, 0), 100)
    }

    var finished: Bool {
        guard videoDuration.isFinite, !videoDuration.isZero else {
            return true
        }
        return progress >= Double(watchedThreshold)
    }

    var watchedAtString: String? {
        guard let watchedAt else {
            return nil
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: watchedAt, relativeTo: Date())
    }

    var timeToRestart: CMTime? {
        finished ? nil : saveHistory ? .secondsInDefaultTimescale(stoppedAt) : nil
    }

    var video: Video {
        let url = URL(string: videoID)

        if !Video.VideoID.isValid(videoID) {
            if let url {
                return .local(url)
            }
        }

        return Video(app: app ?? AccountsModel.shared.current?.app ?? .local, instanceURL: instanceURL, videoID: videoID)
    }

    var isShowingProgress: Bool {
        saveHistory && showWatchingProgress && (finished || progress > 0)
    }
}
