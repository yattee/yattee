//
//  LocalFileClient.swift
//  Yattee
//
//  Client for browsing local folders from Files app (iOS) or filesystem (macOS).
//

import Foundation
import UniformTypeIdentifiers

/// Sync, thread-safe cache of resolved local-folder root URLs keyed by source ID.
///
/// The persisted `MediaSource.url` captures the path of the app container at folder-pick time.
/// On iOS the container UUID changes across reinstall/restore, so that path becomes stale.
/// The security-scoped bookmark resolves to the *current* container; this resolver lets
/// synchronous call sites (`MediaFile.url`) read the freshly resolved path without
/// re-resolving the bookmark on every access.
enum LocalFolderURLResolver {
    private static var cache: [UUID: URL] = [:]
    private static var persistentAccess: [UUID: URL] = [:]
    private static let lock = NSLock()

    static func setResolvedURL(_ url: URL, for sourceID: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache[sourceID] = url

        // Acquire (and hold) a security-scoped access token for this URL so that
        // background readers — particularly MPV/libavformat — can open files inside
        // it long after the directory enumeration that resolved the bookmark has
        // returned. Without this, iOS revokes the scope as soon as the matching
        // `defer { stopAccessing... }` fires, and subsequent file opens fail with
        // a generic "loading failed" error.
        if persistentAccess[sourceID]?.path != url.path {
            if let previous = persistentAccess[sourceID] {
                previous.stopAccessingSecurityScopedResource()
            }
            let didStart = url.startAccessingSecurityScopedResource()
            if didStart {
                persistentAccess[sourceID] = url
            } else {
                persistentAccess.removeValue(forKey: sourceID)
            }
        }
    }

    static func resolvedURL(for sourceID: UUID) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return cache[sourceID]
    }

    static func clear(_ sourceID: UUID) {
        lock.lock(); defer { lock.unlock() }
        cache.removeValue(forKey: sourceID)
        if let previous = persistentAccess.removeValue(forKey: sourceID) {
            previous.stopAccessingSecurityScopedResource()
        }
    }
}

/// Actor-based client for local file system operations.
actor LocalFileClient {
    private let fileManager = FileManager.default

    // MARK: - Public Methods

    /// Lists files in a local folder.
    /// - Parameters:
    ///   - url: The folder URL to list.
    ///   - source: The media source configuration.
    /// - Returns: Array of files and folders in the directory.
    func listFiles(
        in url: URL,
        source: MediaSource,
        rootURL: URL? = nil
    ) async throws -> [MediaFile] {
        guard source.type == .localFolder else {
            throw MediaSourceError.unknown("Invalid source type for LocalFileClient")
        }

        // Start accessing security-scoped resource on the resolved root if available,
        // otherwise on the directory itself. Bookmark access is granted for the root,
        // and child URLs inherit access while it is held.
        let accessURL = rootURL ?? url
        let didStartAccessing = accessURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                accessURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw MediaSourceError.pathNotFound(url.path)
        }

        guard isDirectory.boolValue else {
            throw MediaSourceError.notADirectory
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .contentTypeKey
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw MediaSourceError.accessDenied
        }

        var files: [MediaFile] = []

        // Use the resolved root URL (from the bookmark) for relative-path computation.
        // Falling back to the directory URL itself yields paths relative to that directory,
        // which still avoids the stale-container-UUID prefix problem.
        let baseForRelative = rootURL ?? url

        for fileURL in contents {
            if let file = try? createMediaFile(from: fileURL, source: source, rootURL: baseForRelative) {
                files.append(file)
            }
        }

        // Sort: directories first, then alphabetically
        files.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return files
    }

    /// Lists files relative to the source root URL.
    /// - Parameters:
    ///   - path: Path relative to source URL (or empty for root).
    ///   - source: The media source configuration.
    /// - Returns: Array of files and folders.
    func listFiles(
        at path: String,
        source: MediaSource
    ) async throws -> [MediaFile] {
        let baseURL = resolveBaseURL(for: source)
        LocalFolderURLResolver.setResolvedURL(baseURL, for: source.id)

        // Defensive normalization: if `path` is absolute (legacy MediaFile entries
        // produced before relative paths were computed correctly), strip everything
        // up to and including the source folder name so the appendPathComponent below
        // doesn't double-up the path under a stale container UUID.
        let normalizedPath = Self.normalizeAbsolutePath(path, sourceFolderName: baseURL.lastPathComponent)

        let url: URL
        if normalizedPath.isEmpty || normalizedPath == "/" {
            url = baseURL
        } else {
            let cleanPath = normalizedPath.hasPrefix("/") ? String(normalizedPath.dropFirst()) : normalizedPath
            url = baseURL.appendingPathComponent(cleanPath)
        }
        return try await listFiles(in: url, source: source, rootURL: baseURL)
    }

    /// Picks the most likely valid root URL for a local-folder source.
    ///
    /// On iOS, the app container UUID changes across reinstall/restore. Two storage
    /// locations capture the path independently and either can become stale:
    ///   - `source.url` — captured at folder-pick time, may be updated when the source
    ///     is re-saved.
    ///   - `source.bookmarkData` — security-scoped bookmark; for paths inside the app's
    ///     own Documents directory, iOS does not migrate the captured path across
    ///     container changes, so the resolved URL can point at the previous container.
    ///
    /// We try the bookmark first, fall back to `source.url`, and prefer whichever
    /// actually exists on disk. If both exist, the bookmark wins (its security scope
    /// matters for folders picked outside the app sandbox). If neither exists we still
    /// return something so the caller's error path triggers normally.
    private func resolveBaseURL(for source: MediaSource) -> URL {
        var bookmarkURL: URL?
        if let bookmarkData = source.bookmarkData {
            bookmarkURL = try? resolveBookmark(bookmarkData)
        }

        let bookmarkExists = bookmarkURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
        if let bookmarkURL, bookmarkExists {
            return bookmarkURL
        }
        if fileManager.fileExists(atPath: source.url.path) {
            return source.url
        }
        return bookmarkURL ?? source.url
    }

    /// Strips a leading absolute container path (`/private/var/.../Documents/<sourceFolder>/...`)
    /// down to the portion after the source folder, returning a path relative to the source root.
    /// No-op for already-relative paths.
    static func normalizeAbsolutePath(_ path: String, sourceFolderName: String) -> String {
        guard path.hasPrefix("/") else { return path }
        let marker = "/\(sourceFolderName)/"
        if let range = path.range(of: marker, options: .backwards) {
            return String(path[range.upperBound...])
        }
        let suffix = "/\(sourceFolderName)"
        if path.hasSuffix(suffix) {
            return ""
        }
        return path
    }

    // MARK: - Security-Scoped Bookmarks

    /// Creates a security-scoped bookmark for persistent folder access.
    /// - Parameter url: The folder URL to bookmark.
    /// - Returns: Bookmark data that can be stored for later access.
    func createBookmark(for url: URL) throws -> Data {
        // Start accessing security-scoped resource if needed
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [
            .withSecurityScope,
            .securityScopeAllowOnlyReadAccess
        ]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif

        do {
            return try url.bookmarkData(
                options: options,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw MediaSourceError.unknown("Failed to create bookmark: \(error.localizedDescription)")
        }
    }

    /// Resolves a security-scoped bookmark to a URL.
    /// - Parameter bookmarkData: The stored bookmark data.
    /// - Returns: The resolved URL with access granted.
    func resolveBookmark(_ bookmarkData: Data) throws -> URL {
        var isStale = false

        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw MediaSourceError.bookmarkResolutionFailed
        }

        if isStale {
            // Bookmark is stale, but we might still have access
            // The caller should re-create the bookmark if possible
            throw MediaSourceError.bookmarkResolutionFailed
        }

        return url
    }

    /// Resolves bookmark and starts accessing the security-scoped resource.
    /// - Parameter bookmarkData: The stored bookmark data.
    /// - Returns: Tuple of (URL, didStartAccessing) - caller must call stopAccessingSecurityScopedResource when done.
    func resolveAndAccessBookmark(_ bookmarkData: Data) throws -> (URL, Bool) {
        let url = try resolveBookmark(bookmarkData)
        let didStart = url.startAccessingSecurityScopedResource()
        return (url, didStart)
    }

    // MARK: - Private Methods

    private func createMediaFile(
        from url: URL,
        source: MediaSource,
        rootURL: URL
    ) throws -> MediaFile {
        let resourceValues = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .contentTypeKey
        ])

        let isDirectory = resourceValues.isDirectory ?? false
        let size = resourceValues.fileSize.map { Int64($0) }
        let modifiedDate = resourceValues.contentModificationDate
        let createdDate = resourceValues.creationDate
        let contentType = resourceValues.contentType

        // Calculate relative path from the resolved source root.
        //
        // Using `source.url.path` here is wrong: that path was captured at folder-pick
        // time and on iOS contains the *original* app container UUID. After reinstall
        // or restore the container UUID changes; `url.path` (from the directory enum)
        // contains the new UUID, so the prefix won't match and the "relative" path
        // would degrade to an absolute path. Always strip against the live root URL
        // we just enumerated from instead.
        let standardizedURLPath = url.standardizedFileURL.path
        let standardizedRootPath = rootURL.standardizedFileURL.path
        var relativePath = standardizedURLPath
        if standardizedURLPath.hasPrefix(standardizedRootPath) {
            relativePath = String(standardizedURLPath.dropFirst(standardizedRootPath.count))
        }
        if relativePath.hasPrefix("/") {
            relativePath = String(relativePath.dropFirst())
        }

        return MediaFile(
            source: source,
            path: relativePath,
            name: url.lastPathComponent,
            isDirectory: isDirectory,
            size: size,
            modifiedDate: modifiedDate,
            createdDate: createdDate,
            mimeType: contentType?.preferredMIMEType
        )
    }
}
