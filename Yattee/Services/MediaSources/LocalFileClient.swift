//
//  LocalFileClient.swift
//  Yattee
//
//  Client for browsing local folders from Files app (iOS) or filesystem (macOS).
//

import Foundation
import UniformTypeIdentifiers

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
        source: MediaSource
    ) async throws -> [MediaFile] {
        guard source.type == .localFolder else {
            throw MediaSourceError.unknown("Invalid source type for LocalFileClient")
        }

        // Start accessing security-scoped resource
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
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

        for fileURL in contents {
            if let file = try? createMediaFile(from: fileURL, source: source) {
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
        // Resolve bookmark to get valid URL (required after app restart on iOS)
        let baseURL: URL
        if let bookmarkData = source.bookmarkData {
            baseURL = try resolveBookmark(bookmarkData)
        } else {
            baseURL = source.url
        }

        let url: URL
        if path.isEmpty || path == "/" {
            url = baseURL
        } else {
            let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
            url = baseURL.appendingPathComponent(cleanPath)
        }
        return try await listFiles(in: url, source: source)
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
        source: MediaSource
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

        // Calculate relative path from source root
        let relativePath = url.path.replacingOccurrences(
            of: source.url.path,
            with: ""
        )

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
