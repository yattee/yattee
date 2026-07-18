//
//  StoryboardService.swift
//  Yattee
//
//  Service for loading and extracting storyboard preview thumbnails.
//

import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Parsed VTT entry mapping time range to image URL and crop region
struct VTTEntry: Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let imageURL: URL
    let cropRect: CGRect? // From #xywh fragment, nil if not present
}

/// Service for loading storyboard sprite sheets and extracting individual thumbnails.
actor StoryboardService {
    /// Shared instance for use across the app.
    static let shared = StoryboardService()

    /// Cache of loaded sprite sheets (sheetURL -> image)
    private var sheetCache: [URL: PlatformImage] = [:]

    /// Currently loading sheets (to prevent duplicate loads)
    private var loadingSheets: Set<URL> = []

    /// Maximum number of sheets to keep in memory
    private let maxCachedSheets = 10

    /// Cached VTT entries per storyboard proxy URL
    private var vttCache: [URL: [VTTEntry]] = [:]

    /// Currently loading VTT files (to prevent duplicate loads)
    private var loadingVTT: Set<URL> = []

    // MARK: - Public API

    /// Extracts a thumbnail for a specific time from the storyboard.
    /// - Parameters:
    ///   - time: The time in seconds
    ///   - storyboard: The storyboard configuration
    /// - Returns: The extracted thumbnail, or nil if not available
    func thumbnail(for time: TimeInterval, from storyboard: Storyboard) async -> PlatformImage? {
        // Try VTT-based loading first (proxied URL)
        if let entries = await getOrLoadVTT(for: storyboard), !entries.isEmpty {
            if let entry = findEntry(for: time, in: entries) {
                if let image = sheetCache[entry.imageURL] {
                    // Use VTT crop rect if available, otherwise calculate from storyboard
                    let cropRect = entry.cropRect ?? storyboard.cropRect(for: time) ?? CGRect.zero
                    return image.cropped(to: cropRect)
                }
            }
        }

        // Fallback to direct URL loading (templateUrl)
        guard let cropRect = storyboard.cropRect(for: time),
              let position = storyboard.position(for: time),
              let sheetURL = storyboard.sheetURL(for: position.sheetIndex),
              let sheet = sheetCache[sheetURL]
        else {
            return nil
        }

        return sheet.cropped(to: cropRect)
    }

    /// Loads the sprite sheet for the given time if not already cached.
    /// Uses VTT if available, otherwise falls back to direct URL.
    /// - Parameters:
    ///   - time: The time in seconds
    ///   - storyboard: The storyboard configuration
    func loadSheet(for time: TimeInterval, from storyboard: Storyboard) async {
        // Try VTT-based loading first
        if let entries = await getOrLoadVTT(for: storyboard), !entries.isEmpty {
            if let entry = findEntry(for: time, in: entries) {
                await loadSheetByURL(entry.imageURL)
                return
            }
        }

        // Fallback to direct URL
        guard let position = storyboard.position(for: time),
              let sheetURL = storyboard.sheetURL(for: position.sheetIndex)
        else {
            return
        }

        await loadSheetByURL(sheetURL)
    }

    /// Preloads sheets for a range of times (current + adjacent).
    /// - Parameters:
    ///   - time: The center time in seconds
    ///   - storyboard: The storyboard configuration
    func preloadNearbySheets(around time: TimeInterval, from storyboard: Storyboard) async {
        // Try VTT-based loading
        if let entries = await getOrLoadVTT(for: storyboard), !entries.isEmpty {
            // Find entries for current time and nearby times
            let timesToLoad = [time - storyboard.intervalSeconds * 25, time, time + storyboard.intervalSeconds * 25]
            var urlsToLoad: Set<URL> = []

            for t in timesToLoad where t >= 0 {
                if let entry = findEntry(for: t, in: entries) {
                    urlsToLoad.insert(entry.imageURL)
                }
            }

            await withTaskGroup(of: Void.self) { group in
                for url in urlsToLoad {
                    if sheetCache[url] == nil, !loadingSheets.contains(url) {
                        group.addTask {
                            await self.loadSheetByURL(url)
                        }
                    }
                }
            }
            return
        }

        // Fallback to direct URL loading
        guard let position = storyboard.position(for: time) else { return }

        let indices = [position.sheetIndex - 1, position.sheetIndex, position.sheetIndex + 1]
            .filter { $0 >= 0 && $0 < storyboard.storyboardCount }

        await withTaskGroup(of: Void.self) { group in
            for index in indices {
                guard let url = storyboard.sheetURL(for: index) else { continue }
                if sheetCache[url] == nil, !loadingSheets.contains(url) {
                    group.addTask {
                        await self.loadSheetByURL(url)
                    }
                }
            }
        }
    }

    /// Clears all caches.
    /// Call this when the video changes.
    func clearCache() {
        sheetCache.removeAll()
        loadingSheets.removeAll()
        vttCache.removeAll()
        loadingVTT.removeAll()
    }

    // MARK: - VTT Loading and Parsing

    /// Gets cached VTT entries or loads them from the proxy URL
    private func getOrLoadVTT(for storyboard: Storyboard) async -> [VTTEntry]? {
        guard let proxyUrl = storyboard.proxyUrl else {
            return nil
        }

        // Construct absolute VTT URL
        let vttURL: URL?
        if proxyUrl.hasPrefix("http://") || proxyUrl.hasPrefix("https://") {
            // Already an absolute URL
            vttURL = URL(string: proxyUrl)
        } else if let baseURL = storyboard.instanceBaseURL {
            // Relative URL - prepend base URL
            var baseString = baseURL.absoluteString
            if baseString.hasSuffix("/"), proxyUrl.hasPrefix("/") {
                baseString = String(baseString.dropLast())
            }
            vttURL = URL(string: baseString + proxyUrl)
        } else {
            return nil
        }

        guard let vttURL else {
            return nil
        }

        // Check cache
        if let cached = vttCache[vttURL] {
            return cached
        }

        // Check if already loading
        guard !loadingVTT.contains(vttURL) else {
            // Wait a bit and try cache again
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return vttCache[vttURL]
        }

        // Load VTT
        loadingVTT.insert(vttURL)
        defer { loadingVTT.remove(vttURL) }

        do {
            let (data, response) = try await URLSession.shared.data(from: vttURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                return nil
            }

            let entries = parseVTT(data, baseURL: vttURL)
            if !entries.isEmpty {
                vttCache[vttURL] = entries
            }
            return entries

        } catch {
            return nil
        }
    }

    /// Parses WebVTT data into VTTEntry array
    /// - Parameters:
    ///   - data: The VTT file data
    ///   - baseURL: Base URL for resolving relative image paths
    private func parseVTT(_ data: Data, baseURL: URL) -> [VTTEntry] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var entries: [VTTEntry] = []
        let lines = text.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Look for timestamp line: "00:00:00.000 --> 00:00:10.000"
            if line.contains("-->") {
                let times = line.components(separatedBy: "-->")
                if times.count == 2,
                   let start = parseTimestamp(times[0].trimmingCharacters(in: .whitespaces)),
                   let end = parseTimestamp(times[1].trimmingCharacters(in: .whitespaces))
                {
                    // Next line is the URL
                    i += 1
                    if i < lines.count {
                        let urlLine = lines[i].trimmingCharacters(in: .whitespaces)
                        if !urlLine.isEmpty, let (url, cropRect) = parseImageURL(urlLine, baseURL: baseURL) {
                            entries.append(VTTEntry(
                                startTime: start,
                                endTime: end,
                                imageURL: url,
                                cropRect: cropRect
                            ))
                        }
                    }
                }
            }
            i += 1
        }

        return entries
    }

    /// Parses a timestamp string like "00:00:00.000" or "00:00.000" to TimeInterval
    private func parseTimestamp(_ str: String) -> TimeInterval? {
        let components = str.components(separatedBy: ":")
        guard components.count >= 2 else { return nil }

        if components.count == 3 {
            // HH:MM:SS.mmm
            guard let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2])
            else {
                return nil
            }
            return hours * 3600 + minutes * 60 + seconds
        } else {
            // MM:SS.mmm
            guard let minutes = Double(components[0]),
                  let seconds = Double(components[1])
            else {
                return nil
            }
            return minutes * 60 + seconds
        }
    }

    /// Parses an image URL line, extracting the URL and optional #xywh crop fragment
    /// - Parameters:
    ///   - str: The URL string from VTT (may be relative or absolute)
    ///   - baseURL: Base URL for resolving relative paths
    private func parseImageURL(_ str: String, baseURL: URL) -> (URL, CGRect?)? {
        // Split by # to separate URL from fragment
        let parts = str.components(separatedBy: "#")
        guard let urlString = parts.first, !urlString.isEmpty else {
            return nil
        }

        // Resolve the URL (handle both absolute and relative URLs)
        let url: URL?
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            // Already absolute
            url = URL(string: urlString)
        } else if urlString.hasPrefix("/") {
            // Relative to host root - extract scheme and host from baseURL
            if let scheme = baseURL.scheme, let host = baseURL.host {
                let port = baseURL.port.map { ":\($0)" } ?? ""
                url = URL(string: "\(scheme)://\(host)\(port)\(urlString)")
            } else {
                url = nil
            }
        } else {
            // Relative to current path
            url = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
        }

        guard let resolvedURL = url else {
            return nil
        }

        var cropRect: CGRect?

        // Parse #xywh=x,y,w,h fragment if present
        if parts.count > 1 {
            let fragment = parts[1]
            if fragment.hasPrefix("xywh=") {
                let coords = fragment.dropFirst(5).components(separatedBy: ",")
                if coords.count == 4,
                   let x = Double(coords[0]),
                   let y = Double(coords[1]),
                   let w = Double(coords[2]),
                   let h = Double(coords[3])
                {
                    cropRect = CGRect(x: x, y: y, width: w, height: h)
                }
            }
        }

        return (resolvedURL, cropRect)
    }

    /// Finds the VTT entry that contains the given time
    private func findEntry(for time: TimeInterval, in entries: [VTTEntry]) -> VTTEntry? {
        // Binary search would be more efficient for large entry lists,
        // but linear search is fine for typical storyboard sizes
        for entry in entries {
            if time >= entry.startTime, time < entry.endTime {
                return entry
            }
        }
        // If time is past all entries, return the last one
        if let last = entries.last, time >= last.endTime {
            return last
        }
        return entries.first
    }

    // MARK: - Sheet Loading

    private func loadSheetByURL(_ url: URL) async {
        guard sheetCache[url] == nil, !loadingSheets.contains(url) else {
            return
        }

        loadingSheets.insert(url)
        defer { loadingSheets.remove(url) }

        do {
            let data: Data

            if url.isFileURL {
                // Local file - read directly from disk
                data = try Data(contentsOf: url)
            } else {
                // Network request
                let (networkData, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }
                data = networkData
            }

            guard let image = PlatformImage(data: data) else {
                return
            }

            // Evict oldest sheet if cache is full
            if sheetCache.count >= maxCachedSheets {
                if let oldest = sheetCache.keys.first {
                    sheetCache.removeValue(forKey: oldest)
                }
            }
            sheetCache[url] = image
        } catch {
            // Silent failure - storyboard loading is non-critical
        }
    }
}
