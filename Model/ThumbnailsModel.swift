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
        let qualities = [Thumbnail.Quality.default]

        for quality in qualities {
            let url = video.thumbnailURL(quality: quality)
            if !isUnloadable(url) {
                return url
            }
        }

        return nil
    }
}
