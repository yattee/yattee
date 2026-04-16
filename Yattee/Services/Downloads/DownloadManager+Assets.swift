//
//  DownloadManager+Assets.swift
//  Yattee
//
//  Storyboard and thumbnail download operations for DownloadManager.
//

import Foundation

#if !os(tvOS)

extension DownloadManager {
    // MARK: - Storyboard Download

    /// Returns true if `proxyUrl` clearly points at a direct image (e.g. a YouTube CDN
    /// `.jpg` URL returned by yattee-server) rather than a VTT proxy path.
    /// In that case fetching it and trying to parse as WebVTT would be wasted bandwidth
    /// and produces an empty URL list, so we skip straight to the templateUrl fallback.
    static func proxyUrlLooksLikeImage(_ urlString: String) -> Bool {
        // Strip the query string; common YouTube URLs carry huge `sqp` / `sigh` params.
        let pathOnly = urlString.split(separator: "?", maxSplits: 1).first.map(String.init) ?? urlString
        let lower = pathOnly.lowercased()
        return lower.hasSuffix(".jpg")
            || lower.hasSuffix(".jpeg")
            || lower.hasSuffix(".png")
            || lower.hasSuffix(".webp")
    }


    /// Start downloading storyboard sprite sheets sequentially
    func startStoryboardDownload(downloadID: UUID) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }),
              let storyboard = activeDownloads[index].storyboard else {
            return
        }

        // Cancel any existing storyboard task
        storyboardTasks[downloadID]?.cancel()

        let download = activeDownloads[index]
        let videoID = download.videoID.videoID
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        let task = Task {
            // Create storyboard directory
            let storyboardDirName = "\(videoID)_storyboards"
            let storyboardDir = downloadsDirectory().appendingPathComponent(storyboardDirName, isDirectory: true)

            do {
                if !fileManager.fileExists(atPath: storyboardDir.path) {
                    try fileManager.createDirectory(at: storyboardDir, withIntermediateDirectories: true)
                }
            } catch {
                LoggingService.shared.logDownloadError("Failed to create storyboard directory", error: error)
                handleStoryboardCompletion(downloadID: downloadID, success: false)
                return
            }

            // Diagnostic: log the selected storyboard variant so we can tell
            // which server shape we are dealing with (Invidious VTT vs yattee-server direct URLs).
            let proxySample = storyboard.proxyUrl.map { String($0.prefix(120)) } ?? "<nil>"
            let templateSample = String(storyboard.templateUrl.prefix(120))
            LoggingService.shared.debug(
                "[Storyboard] Starting download for \(videoID): \(storyboard.width)x\(storyboard.height), sheets=\(storyboard.storyboardCount)",
                category: .downloads,
                details: "proxyUrl=\(proxySample) templateUrl=\(templateSample)"
            )

            // First, try to get VTT from proxy URL to extract actual image URLs.
            // Some backends (yattee-server after innertube switch) return a direct image
            // URL in the `url` field instead of a VTT proxy path, so skip the VTT round-trip
            // when the URL obviously points at an image resource.
            var imageURLs: [URL] = []

            if let proxyUrl = storyboard.proxyUrl {
                if Self.proxyUrlLooksLikeImage(proxyUrl) {
                    LoggingService.shared.debug(
                        "[Storyboard] Skipping VTT fetch — proxyUrl looks like a direct image, using templateUrl fallback",
                        category: .downloads
                    )
                } else {
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
                        vttURL = nil
                    }

                    if let vttURL {
                        do {
                            let (vttData, response) = try await URLSession.shared.data(from: vttURL)
                            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                            imageURLs = parseVTTForImageURLs(vttData, baseURL: vttURL)
                            LoggingService.shared.debug(
                                "[Storyboard] VTT fetch OK (status=\(status), bytes=\(vttData.count)) parsed \(imageURLs.count) URLs",
                                category: .downloads
                            )
                        } catch {
                            LoggingService.shared.debug(
                                "[Storyboard] VTT fetch failed: \(error.localizedDescription) — will fall back to direct URLs",
                                category: .downloads
                            )
                        }
                    } else {
                        LoggingService.shared.debug(
                            "[Storyboard] Could not construct VTT URL from proxyUrl, falling back to direct URLs",
                            category: .downloads
                        )
                    }
                }
            }

            // If VTT parsing failed, fall back to direct URLs (may not work if blocked)
            if imageURLs.isEmpty, storyboard.storyboardCount > 0 {
                var nilCount = 0
                for sheetIndex in 0..<storyboard.storyboardCount {
                    if let url = storyboard.directSheetURL(for: sheetIndex) {
                        imageURLs.append(url)
                    } else {
                        nilCount += 1
                    }
                }
                let firstSample = imageURLs.first.map { String($0.absoluteString.prefix(160)) } ?? "<none>"
                LoggingService.shared.debug(
                    "[Storyboard] directSheetURL fallback produced \(imageURLs.count)/\(storyboard.storyboardCount) URLs (nil: \(nilCount))",
                    category: .downloads,
                    details: "first=\(firstSample)"
                )
            }

            let totalSheets = imageURLs.count
            var completedSheets = 0

            if totalSheets == 0 {
                LoggingService.shared.debug(
                    "[Storyboard] No sheet URLs to download after VTT + fallback — will mark as failed",
                    category: .downloads
                )
            }

            // Download each sprite sheet sequentially
            for (sheetIndex, sheetURL) in imageURLs.enumerated() {
                guard !Task.isCancelled else { return }

                // Filename must match the `sb_M$M.jpg` template used by
                // `Storyboard.localStoryboard(...)` after `M$M` → `M{index}` substitution
                // in `Storyboard.directSheetURL(for:)`, otherwise local playback won't
                // resolve the sheets.
                let fileName = "sb_M\(sheetIndex).jpg"
                let fileURL = storyboardDir.appendingPathComponent(fileName)

                // Skip if already downloaded
                if fileManager.fileExists(atPath: fileURL.path) {
                    completedSheets += 1
                    updateStoryboardProgress(downloadID: downloadID, completed: completedSheets, total: totalSheets)
                    continue
                }

                do {
                    let (data, response) = try await URLSession.shared.data(from: sheetURL)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        LoggingService.shared.debug(
                            "[Storyboard] Sheet \(sheetIndex) skipped — HTTP \(status) (bytes=\(data.count))",
                            category: .downloads,
                            details: String(sheetURL.absoluteString.prefix(160))
                        )
                        continue
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

                    // Verify it's actually an image
                    guard contentType.contains("image") || data.count > 50000 else {
                        LoggingService.shared.debug(
                            "[Storyboard] Sheet \(sheetIndex) skipped — unexpected content (type=\(contentType), bytes=\(data.count))",
                            category: .downloads
                        )
                        continue
                    }

                    try data.write(to: fileURL)
                    completedSheets += 1
                    updateStoryboardProgress(downloadID: downloadID, completed: completedSheets, total: totalSheets)

                } catch {
                    LoggingService.shared.debug(
                        "[Storyboard] Sheet \(sheetIndex) errored: \(error.localizedDescription)",
                        category: .downloads,
                        details: String(sheetURL.absoluteString.prefix(160))
                    )
                }
            }

            // Complete storyboard phase
            let success = completedSheets > 0
            LoggingService.shared.debug(
                "[Storyboard] Download phase finished: \(completedSheets)/\(totalSheets) sheets succeeded",
                category: .downloads
            )
            finalizeStoryboardDownload(
                downloadID: downloadID,
                storyboardDirName: storyboardDirName,
                success: success
            )
        }

        storyboardTasks[downloadID] = task
    }

    /// Parse VTT data to extract unique image URLs
    /// - Parameters:
    ///   - data: The VTT file data
    ///   - baseURL: Base URL for resolving relative image paths
    func parseVTTForImageURLs(_ data: Data, baseURL: URL) -> [URL] {
        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        var uniqueURLs: [URL] = []
        var seenURLs: Set<String> = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines, WEBVTT header, and timestamp lines
            guard !trimmedLine.isEmpty,
                  !trimmedLine.hasPrefix("WEBVTT"),
                  !trimmedLine.contains("-->") else {
                continue
            }

            // Extract URL part (before #xywh fragment)
            let urlString = trimmedLine.components(separatedBy: "#").first ?? trimmedLine

            // Resolve the URL (handle both absolute and relative URLs)
            let resolvedURL: URL?
            if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                // Already absolute
                resolvedURL = URL(string: urlString)
            } else if urlString.hasPrefix("/") {
                // Relative to host root - extract scheme and host from baseURL
                if let scheme = baseURL.scheme, let host = baseURL.host {
                    let port = baseURL.port.map { ":\($0)" } ?? ""
                    resolvedURL = URL(string: "\(scheme)://\(host)\(port)\(urlString)")
                } else {
                    resolvedURL = nil
                }
            } else if !urlString.isEmpty {
                // Relative to current path
                resolvedURL = URL(string: urlString, relativeTo: baseURL)?.absoluteURL
            } else {
                resolvedURL = nil
            }

            // Only add unique URLs
            if let url = resolvedURL, !seenURLs.contains(url.absoluteString) {
                seenURLs.insert(url.absoluteString)
                uniqueURLs.append(url)
            }
        }

        return uniqueURLs
    }

    /// Update storyboard download progress
    func updateStoryboardProgress(downloadID: UUID, completed: Int, total: Int) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }
        activeDownloads[index].storyboardProgress = Double(completed) / Double(total)
        recalculateOverallProgress(for: index)
    }

    /// Finalize storyboard download phase
    func finalizeStoryboardDownload(downloadID: UUID, storyboardDirName: String, success: Bool) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        if success {
            activeDownloads[index].localStoryboardPath = storyboardDirName
            activeDownloads[index].storyboardProgress = 1.0

            // Calculate total storyboard size
            let storyboardDir = downloadsDirectory().appendingPathComponent(storyboardDirName)
            activeDownloads[index].storyboardTotalBytes = directorySize(at: storyboardDir)

            LoggingService.shared.logDownload(
                "Storyboard saved: \(activeDownloads[index].videoID.id)",
                details: storyboardDirName
            )
        } else {
            // Mark as complete even on failure (non-blocking)
            activeDownloads[index].storyboardProgress = 1.0
            LoggingService.shared.logDownload(
                "Storyboard download failed (non-fatal): \(activeDownloads[index].videoID.id)"
            )
        }

        storyboardTasks.removeValue(forKey: downloadID)
        recalculateOverallProgress(for: index)
        saveDownloads()

        Task {
            await checkAndCompleteDownload(downloadID: downloadID)
        }
    }

    /// Handle storyboard completion for error cases
    func handleStoryboardCompletion(downloadID: UUID, success: Bool) {
        finalizeStoryboardDownload(downloadID: downloadID, storyboardDirName: "", success: success)
    }

    // MARK: - Thumbnail Download

    /// Downloads video and channel thumbnails for offline Now Playing artwork.
    /// This is a best-effort operation - failures do not affect download completion.
    func startThumbnailDownload(downloadID: UUID) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        // Cancel any existing thumbnail task
        thumbnailTasks[downloadID]?.cancel()

        let download = activeDownloads[index]
        activeDownloads[index].downloadPhase = .thumbnail

        let task = Task {
            let videoID = sanitizedVideoID(download.videoID)
            var thumbnailPath: String?
            var channelThumbnailPath: String?

            // Download video thumbnail (best quality) - best-effort, ignore failures
            if let thumbnailURL = download.thumbnailURL {
                thumbnailPath = await downloadThumbnail(
                    from: thumbnailURL,
                    filename: "\(videoID)_thumbnail.jpg"
                )
            }

            // Download channel thumbnail - best-effort, ignore failures
            if let channelURL = download.channelThumbnailURL {
                let channelID = download.channelID
                    .replacingOccurrences(of: ":", with: "_")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "\\", with: "_")
                channelThumbnailPath = await downloadThumbnail(
                    from: channelURL,
                    filename: "\(channelID)_avatar.jpg"
                )
            }

            // Always complete, regardless of thumbnail success/failure
            finalizeThumbnailDownload(
                downloadID: downloadID,
                thumbnailPath: thumbnailPath,
                channelThumbnailPath: channelThumbnailPath
            )
        }

        thumbnailTasks[downloadID] = task
    }

    /// Downloads a single thumbnail image.
    /// Returns the filename on success, nil on failure. Never throws.
    func downloadThumbnail(from url: URL, filename: String) async -> String? {
        let fileURL = downloadsDirectory().appendingPathComponent(filename)

        // Skip if already downloaded
        if fileManager.fileExists(atPath: fileURL.path) {
            return filename
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  !data.isEmpty else {
                LoggingService.shared.debug(
                    "[Downloads] Thumbnail download returned non-200 or empty: \(filename)",
                    category: .downloads
                )
                return nil
            }

            try data.write(to: fileURL, options: .atomic)
            LoggingService.shared.debug(
                "[Downloads] Thumbnail saved: \(filename)",
                category: .downloads
            )
            return filename
        } catch {
            // Log but don't propagate - thumbnail failure is non-fatal
            LoggingService.shared.debug(
                "[Downloads] Thumbnail download failed (non-fatal): \(filename) - \(error.localizedDescription)",
                category: .downloads
            )
            return nil
        }
    }

    /// Finalizes thumbnail phase and completes the download.
    /// Called regardless of whether thumbnails succeeded or failed.
    func finalizeThumbnailDownload(
        downloadID: UUID,
        thumbnailPath: String?,
        channelThumbnailPath: String?
    ) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        // Set paths (will be nil if download failed - that's fine)
        activeDownloads[index].localThumbnailPath = thumbnailPath
        activeDownloads[index].localChannelThumbnailPath = channelThumbnailPath

        thumbnailTasks.removeValue(forKey: downloadID)

        if thumbnailPath != nil || channelThumbnailPath != nil {
            LoggingService.shared.logDownload(
                "Thumbnails saved: \(activeDownloads[index].videoID.id)",
                details: "video: \(thumbnailPath ?? "none"), channel: \(channelThumbnailPath ?? "none")"
            )
        }

        saveDownloads()

        // Thumbnail phase is complete - finalize the download
        // (all other phases were already complete when thumbnail download started)
        Task {
            await completeMultiFileDownload(downloadID: downloadID)
        }
    }

    // MARK: - Helpers

    /// Helper to sanitize video ID for use in filenames
    func sanitizedVideoID(_ videoID: VideoID) -> String {
        videoID.videoID
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }
}

#endif
