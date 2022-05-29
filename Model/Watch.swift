import CoreData
import CoreMedia
import Defaults
import Foundation

@objc(Watch)
final class Watch: NSManagedObject, Identifiable {
    @Default(.watchedThreshold) private var watchedThreshold
    @Default(.saveHistory) private var saveHistory
}

extension Watch {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Watch> {
        NSFetchRequest<Watch>(entityName: "Watch")
    }

    @NSManaged var videoID: String
    @NSManaged var videoDuration: Double

    @NSManaged var watchedAt: Date?
    @NSManaged var stoppedAt: Double

    var progress: Double {
        guard videoDuration.isFinite, !videoDuration.isZero else {
            return 0
        }

        let progress = (stoppedAt / videoDuration) * 100

        if progress >= Double(watchedThreshold) {
            return 100
        }

        return min(max(progress, 0), 100)
    }

    var finished: Bool {
        progress >= Double(watchedThreshold)
    }

    var watchedAtString: String? {
        guard let watchedAt = watchedAt else {
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
        Video(
            videoID: videoID, title: "", author: "",
            length: 0, published: "", views: -1, channel: Channel(id: "", name: "")
        )
    }
}
