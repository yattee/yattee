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

    func loadableURL(_ url: URL!) -> URL? {
        guard !url.isNil else {
            return nil
        }

        return isUnloadable(url) ? nil : url
    }
}
