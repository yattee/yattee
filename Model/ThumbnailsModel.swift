import Defaults
import Foundation

final class ThumbnailsModel: ObservableObject {
    @Published var unloadable = Set<URL>()

    func insertUnloadable(_ url: URL) {
        unloadable.insert(url)
    }

    func isUnloadable(_ url: URL!) -> Bool {
        guard !url.isNil else {
            return true
        }

        return unloadable.contains(url)
    }

    func best(_ video: Video) -> URL? {
        for quality in availableQualitites {
            let url = video.thumbnailURL(quality: quality)
            if !isUnloadable(url) {
                return url
            }
        }

        return nil
    }

    private var availableQualitites: [Thumbnail.Quality] {
        switch Defaults[.thumbnailsQuality] {
        case .highest:
            return [.maxresdefault, .medium, .default]
        case .medium:
            return [.medium, .default]
        case .low:
            return [.default]
        }
    }
}
