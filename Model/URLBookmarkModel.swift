import Cache
import Foundation
import Logging

struct URLBookmarkModel {
    static var shared = URLBookmarkModel()
    var logger = Logger(label: "stream.yattee.url-bookmark")

    func saveBookmark(_ url: URL) {
        if let bookmarkData = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            try? CacheModel.shared.urlBookmarksStorage?.setObject(bookmarkData, forKey: url.absoluteString)
            logger.info("saved bookmark for \(url.absoluteString)")
        }
    }

    func loadBookmark(_ url: URL) -> URL? {
        logger.info("loading bookmark for \(url.absoluteString)")

        guard let data = try? CacheModel.shared.urlBookmarksStorage?.object(forKey: url.absoluteString) else {
            logger.info("bookmark for \(url.absoluteString) not found")

            return nil
        }
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
