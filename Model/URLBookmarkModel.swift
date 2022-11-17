import Foundation
import Logging

struct URLBookmarkModel {
    static let bookmarkPrefix = "urlbookmark-"
    static var shared = URLBookmarkModel()

    var logger = Logger(label: "stream.yattee.url-bookmark")

    var allBookmarksKeys: [String] {
        guard let defaults = CacheModel.shared.bookmarksDefaults else { return [] }

        return defaults.dictionaryRepresentation().keys.filter { $0.starts(with: Self.bookmarkPrefix) }
    }

    var allURLs: [URL] {
        allBookmarksKeys.compactMap { urlFromBookmark($0) }
    }

    func saveBookmark(_ url: URL) {
        guard let defaults = CacheModel.shared.bookmarksDefaults else {
            logger.error("could not open bookmarks defaults")
            return
        }

        if let bookmarkData = try? url.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmarkData, forKey: bookmarkKey(url))
            logger.info("saved bookmark for \(bookmarkKey(url))")
        } else {
            logger.error("no bookmark data for \(bookmarkKey(url))")
        }
    }

    func loadBookmark(_ url: URL) -> URL? {
        logger.info("loading bookmark for \(bookmarkKey(url))")

        guard let defaults = CacheModel.shared.bookmarksDefaults else {
            logger.error("could not open bookmarks defaults")
            return nil
        }

        if let data = defaults.data(forKey: bookmarkKey(url)) {
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
                logger.info("loaded bookmark for \(bookmarkKey(url))")

                return url
            } catch {
                print("Error resolving bookmark:", error)
                return nil
            }
        } else {
            logger.warning("could not find bookmark for \(bookmarkKey(url))")
            return nil
        }
    }

    func removeBookmark(_ url: URL) {
        logger.info("removing bookmark for \(bookmarkKey(url))")

        guard let defaults = CacheModel.shared.bookmarksDefaults else {
            logger.error("could not open bookmarks defaults")
            return
        }

        defaults.removeObject(forKey: bookmarkKey(url))
    }

    func refreshAll() {
        logger.info("refreshing all bookmarks")

        allURLs.forEach { url in
            if loadBookmark(url) != nil {
                logger.info("bookmark for \(url) exists")
            } else {
                logger.info("bookmark does not exist")
            }
        }
    }

    private func bookmarkKey(_ url: URL) -> String {
        "\(Self.bookmarkPrefix)\(url.absoluteString)"
    }

    private func urlFromBookmark(_ key: String) -> URL? {
        if let urlString = key.components(separatedBy: Self.bookmarkPrefix).last {
            return URL(string: urlString)
        }
        return nil
    }

    private var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
            return [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
            return []
        #endif
    }

    private var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
            return [.withSecurityScope]
        #else
            return []
        #endif
    }
}
