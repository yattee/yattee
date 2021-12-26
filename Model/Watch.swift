import CoreData
import Defaults
import Foundation

@objc(Watch)
final class Watch: NSManagedObject, Identifiable {
    @Default(.watchedThreshold) private var watchedThreshold
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
        return min(max(progress, 0), 100)
    }

    var finished: Bool {
        progress >= Double(watchedThreshold)
    }

    var watchedAtString: String? {
        guard let watchedAt = watchedAt else {
            return nil
        }

        if watchedAt.timeIntervalSinceNow < 5 {
            return "just now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: watchedAt, relativeTo: Date())
    }
}
