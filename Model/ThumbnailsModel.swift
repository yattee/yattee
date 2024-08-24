import Defaults
import Foundation

final class ThumbnailsModel: ObservableObject {
    static var shared = ThumbnailsModel()

    @Published var unloadable = Set<URL>()

    func insertUnloadable(_ url: URL) {
        DispatchQueue.main.async {
            self.unloadable.insert(url)
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
