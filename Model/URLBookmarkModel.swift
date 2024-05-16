import Foundation
import Logging

struct URLBookmarkModel {
    static let bookmarkPrefix = "urlbookmark-"
    static var shared = Self()

    var logger = Logger(label: "stream.yattee.url-bookmark")

    var allBookmarksKeys: [String] {
        guard let defaults = BookmarksCacheModel.shared.defaults else { return [] }

        return defaults.dictionaryRepresentation().keys.filter { $0.starts(with: Self.bookmarkPrefix) }
    }

    var allURLs: [URL] {
        allBookmarksKeys.compactMap { urlFromBookmark($0) }
    }

    func saveBookmark(_ url: URL) {
        var urlForBookmark = url
        if let yatteeSanitizedUrl = url.byReplacingYatteeProtocol() {
            urlForBookmark = yatteeSanitizedUrl
        }

        guard urlForBookmark.isFileURL else {
            logger.error("trying to save bookmark for something that is not a file")
            logger.error("not a file: \(urlForBookmark.absoluteString)")
            return
        }

        guard let defaults = BookmarksCacheModel.shared.defaults else {
            logger.error("could not open bookmarks defaults")
            return
        }

        if let bookmarkData = try? urlForBookmark.bookmarkData(options: bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(bookmarkData, forKey: bookmarkKey(urlForBookmark))
            logger.info("saved bookmark for \(bookmarkKey(urlForBookmark))")
        } else {
            logger.error("no bookmark data for \(urlForBookmark)")
        }
    }

    func saveBookmark(_ url: NSURL) {
        guard url.isFileURL else {
            logger.error("trying to save bookmark for something that is not a file")
            logger.error("not a file: \(url.absoluteString ?? "unknown")")
            return
        }

        guard let defaults = BookmarksCacheModel.shared.defaults else {
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
        var urlForBookmark = url
        if let yatteeSanitizedUrl = url.byReplacingYatteeProtocol() {
            urlForBookmark = yatteeSanitizedUrl
        }

        logger.info("loading bookmark for \(bookmarkKey(urlForBookmark))")

        guard let defaults = BookmarksCacheModel.shared.defaults else {
            logger.error("could not open bookmarks defaults")
            return nil
        }

        if let data = defaults.data(forKey: bookmarkKey(urlForBookmark)) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: bookmarkResolutionOptions,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    saveBookmark(urlForBookmark)
                }
                logger.info("loaded bookmark for \(bookmarkKey(urlForBookmark))")

                return url
            } catch {
                print("Error resolving bookmark:", error)
                return nil
            }
        } else {
            logger.warning("could not find bookmark for \(bookmarkKey(urlForBookmark))")
            return nil
        }
    }

    func removeBookmark(_ url: URL) {
        logger.info("removing bookmark for \(bookmarkKey(url))")

        guard let defaults = BookmarksCacheModel.shared.defaults else {
            logger.error("could not open bookmarks defaults")
            return
        }

        defaults.removeObject(forKey: bookmarkKey(url))
    }

    func refreshAll() {
        logger.info("refreshing all bookmarks")

        for url in allURLs {
            if loadBookmark(url) != nil {
                logger.info("bookmark for \(url) exists")
            } else {
                logger.info("bookmark does not exist")
            }
        }
    }

    private func bookmarkKey(_ url: URL) -> String {
        "\(Self.bookmarkPrefix)\(NSString(string: url.absoluteString).standardizingPath)"
    }

    private func bookmarkKey(_ url: NSURL) -> String {
        "\(Self.bookmarkPrefix)\(url.standardizingPath?.absoluteString ?? "unknown")"
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
