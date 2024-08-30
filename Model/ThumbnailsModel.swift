import Defaults
import Foundation

final class ThumbnailsModel: ObservableObject {
    static var shared = ThumbnailsModel()

    @Published var unloadable = Set<URL>()
    private var retryCounts = [URL: Int]()
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0

    func insertUnloadable(_ url: URL) {
        let retries = (retryCounts[url] ?? 0) + 1

        if retries >= maxRetries {
            DispatchQueue.main.async {
                self.unloadable.insert(url)
                self.retryCounts.removeValue(forKey: url)
            }
        } else {
            DispatchQueue.main.async {
                self.retryCounts[url] = retries
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay) {
                DispatchQueue.main.async {
                    self.retryCounts[url] = retries
                }
            }
        }
    }

    func isUnloadable(_ url: URL!) -> Bool {
        guard !url.isNil else {
            return true
        }

        return unloadable.contains(url)
    }

    func best(_ video: Video) -> (url: URL?, quality: Thumbnail.Quality?) {
        for quality in availableQualitites {
            let url = video.thumbnailURL(quality: quality)
            if !isUnloadable(url) {
                return (url, quality)
            }
        }

        return (nil, nil)
    }

    private var availableQualitites: [Thumbnail.Quality] {
        switch Defaults[.thumbnailsQuality] {
        case .highest:
            return [.maxres, .high, .medium, .default]
        case .high:
            return [.high, .medium, .default]
        case .medium:
            return [.medium, .default]
        case .low:
            return [.default]
        }
    }
}
