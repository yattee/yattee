import Foundation
import Logging

struct URLBookmarkModel {
    static var shared = URLBookmarkModel()
    var logger = Logger(label: "stream.yattee.url-bookmark")

    func saveBookmark(_ url: URL) {
        guard let defaults = CacheModel.shared.bookmarksDefaults else {
            logger.error("could not open bookmarks defaults")
            return
        }

        if let bookmarkData = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmarkData, forKey: url.absoluteString)
            logger.info("saved bookmark for \(url.absoluteString)")
        } else {
            logger.error("no bookmark data for \(url.absoluteString)")
        }
    }

    func loadBookmark(_ url: URL) -> URL? {
        logger.info("loading bookmark for \(url.absoluteString)")

        guard let defaults = CacheModel.shared.bookmarksDefaults else {
            logger.error("could not open bookmarks defaults")
            return nil
        }

        if let data = defaults.data(forKey: url.absoluteString) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: bookmarkResolutionOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    saveBookmark(url)
                }
                logger.info("loaded bookmark for \(url.absoluteString)")

                return url
            } catch {
                print("Error resolving bookmark:", error)
                return nil
            }
        } else {
            logger.warning("could not find bookmark for \(url.absoluteString)")
            return nil
        }
    }

    func removeBookmark(_ url: URL) {
        logger.info("removing bookmark for \(url.absoluteString)")

        guard let defaults = CacheModel.shared.bookmarksDefaults else {
            logger.error("could not open bookmarks defaults")
            return
        }

        defaults.removeObject(forKey: url.absoluteString)
    }

    var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
            return [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
            return []
        #endif
    }

    var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
            return [.withSecurityScope]
        #else
            return []
        #endif
    }
}
