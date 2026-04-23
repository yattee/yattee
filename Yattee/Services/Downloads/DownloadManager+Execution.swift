//
//  DownloadManager+Execution.swift
//  Yattee
//
//  Download execution, progress, completion, and error handling for DownloadManager.
//

import Foundation
import SwiftUI

#if !os(tvOS)

extension DownloadManager {
    // MARK: - Download Execution

    func startNextDownloadIfNeeded() async {
        let currentlyDownloading = activeDownloads.filter { $0.status == .downloading }.count

        guard currentlyDownloading < maxConcurrentDownloads else { return }

        // Find next queued download
        guard let nextIndex = activeDownloads.firstIndex(where: { $0.status == .queued }) else {
            return
        }

        let downloadID = activeDownloads[nextIndex].id
        activeDownloads[nextIndex].status = .downloading
        activeDownloads[nextIndex].startedAt = Date()
        saveDownloads()

        await startDownload(for: downloadID)
    }

    func startDownload(for downloadID: UUID) async {
        guard urlSession != nil else {
            LoggingService.shared.logDownloadError("URLSession not initialized - call setDownloadSettings() first")
            return
        }

        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            LoggingService.shared.logDownloadError("Download not found in activeDownloads: \(downloadID.uuidString)")
            return
        }

        let download = activeDownloads[index]

        LoggingService.shared.logDownload(
            "[Downloads] startDownload called",
            details: "videoID: \(download.videoID.id), videoProgress: \(download.videoProgress), existingTask: \(videoTasks[downloadID] != nil)"
        )

        // Start video download if not completed
        if download.videoProgress < 1.0 {
            startStreamDownload(
                downloadID: downloadID,
                url: download.streamURL,
                phase: .video,
                resumeData: download.resumeData,
                httpHeaders: download.httpHeaders
            )
            LoggingService.shared.logDownload("Starting video: \(download.videoID.id)")
        }

        // Start audio download simultaneously if needed
        if let audioURL = download.audioStreamURL, download.audioProgress < 1.0 {
            startStreamDownload(
                downloadID: downloadID,
                url: audioURL,
                phase: .audio,
                resumeData: download.audioResumeData,
                httpHeaders: download.httpHeaders
            )
            LoggingService.shared.logDownload("Starting audio: \(download.videoID.id)")
        }

        // Start caption download simultaneously if needed
        if let captionURL = download.captionURL, download.captionProgress < 1.0 {
            startStreamDownload(
                downloadID: downloadID,
                url: captionURL,
                phase: .caption,
                resumeData: nil,
                httpHeaders: download.httpHeaders
            )
            LoggingService.shared.logDownload("Starting caption: \(download.videoID.id)")
        }

        // Start storyboard download if available and not complete
        if download.storyboard != nil, download.storyboardProgress < 1.0 {
            startStoryboardDownload(downloadID: downloadID)
        }
    }

    /// Start a download task for a specific stream phase
    func startStreamDownload(
        downloadID: UUID,
        url: URL,
        phase: DownloadPhase,
        resumeData: Data?,
        httpHeaders: [String: String]? = nil
    ) {
        guard urlSession != nil else {
            LoggingService.shared.logDownloadError(
                "[Downloads] URLSession is nil in startStreamDownload (\(phase))",
                error: DownloadError.downloadFailed("URLSession not available - session may be invalidated")
            )
            handleDownloadError(
                downloadID: downloadID,
                phase: phase,
                error: DownloadError.downloadFailed("URLSession not available")
            )
            return
        }

        let task: URLSessionDownloadTask

        if let resumeData {
            var caughtException: NSException?
            var resumeTask: URLSessionDownloadTask?
            let success = tryCatchObjCException({
                resumeTask = self.urlSession.downloadTask(withResumeData: resumeData)
            }, &caughtException)

            guard success, let resumeTask else {
                LoggingService.shared.logDownloadError(
                    "[Downloads] NSException creating resume task (\(phase))",
                    error: DownloadError.downloadFailed("CFNetwork exception: \(caughtException?.reason ?? "unknown")")
                )
                handleDownloadError(
                    downloadID: downloadID,
                    phase: phase,
                    error: DownloadError.downloadFailed("Failed to create download task: \(caughtException?.reason ?? "unknown")")
                )
                return
            }
            task = resumeTask
        } else {
            // Starting fresh without resumeData - reset progress for this phase
            // to avoid jumping when saved progress conflicts with new URLSession progress
            if let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) {
                switch phase {
                case .video:
                    activeDownloads[index].videoProgress = 0
                case .audio:
                    activeDownloads[index].audioProgress = 0
                case .caption:
                    activeDownloads[index].captionProgress = 0
                case .storyboard, .thumbnail, .complete:
                    break
                }
                recalculateOverallProgress(for: index)
            }

            var request = URLRequest(url: url)
            request.setValue(SettingsManager.currentUserAgent(), forHTTPHeaderField: "User-Agent")
            // Add server-provided headers (cookies, referer, etc.)
            if let httpHeaders {
                for (key, value) in httpHeaders {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            var caughtException: NSException?
            var newTask: URLSessionDownloadTask?
            let success = tryCatchObjCException({
                newTask = self.urlSession.downloadTask(with: request)
            }, &caughtException)

            guard success, let newTask else {
                LoggingService.shared.logDownloadError(
                    "[Downloads] NSException creating download task (\(phase))",
                    error: DownloadError.downloadFailed("CFNetwork exception: \(caughtException?.reason ?? "unknown")")
                )
                handleDownloadError(
                    downloadID: downloadID,
                    phase: phase,
                    error: DownloadError.downloadFailed("Failed to create download task: \(caughtException?.reason ?? "unknown")")
                )
                return
            }
            task = newTask
        }

        task.taskDescription = "\(downloadID.uuidString):\(phase.rawValue)"
        setTaskInfo(downloadID, phase: phase, forTask: task.taskIdentifier)

        // Store task in appropriate dictionary
        switch phase {
        case .video:
            videoTasks[downloadID] = task
        case .audio:
            audioTasks[downloadID] = task
        case .caption:
            captionTasks[downloadID] = task
        case .storyboard, .thumbnail, .complete:
            break
        }

        LoggingService.shared.logDownload(
            "[Downloads] Task started (\(phase))",
            details: "taskID: \(task.taskIdentifier), URL: \(url.host ?? "unknown")"
        )
        task.resume()
    }

    // MARK: - Progress Handling

    func handleDownloadProgress(downloadID: UUID, phase: DownloadPhase, bytesWritten: Int64, totalBytes: Int64) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        let download = activeDownloads[index]
        let previousProgress = download.progress
        let now = Date()

        // Update phase-specific progress and speed
        switch phase {
        case .video:
            activeDownloads[index].videoTotalBytes = totalBytes
            activeDownloads[index].videoDownloadedBytes = bytesWritten
            if totalBytes > 0 {
                activeDownloads[index].videoProgress = Double(bytesWritten) / Double(totalBytes)
            }
            // Speed calculation for video
            if let lastTime = download.lastSpeedUpdateTime {
                let timeDelta = now.timeIntervalSince(lastTime)
                if timeDelta >= 0.5 {
                    let bytesDelta = bytesWritten - download.lastSpeedBytes
                    let speed = Int64(Double(bytesDelta) / timeDelta)
                    activeDownloads[index].videoDownloadSpeed = max(0, speed)
                    activeDownloads[index].downloadSpeed = max(0, speed)
                    activeDownloads[index].lastSpeedUpdateTime = now
                    activeDownloads[index].lastSpeedBytes = bytesWritten
                }
            } else {
                activeDownloads[index].lastSpeedUpdateTime = now
                activeDownloads[index].lastSpeedBytes = bytesWritten
            }

        case .audio:
            activeDownloads[index].audioTotalBytes = totalBytes
            activeDownloads[index].audioDownloadedBytes = bytesWritten
            if totalBytes > 0 {
                activeDownloads[index].audioProgress = Double(bytesWritten) / Double(totalBytes)
            }
            // Speed calculation for audio - use separate tracking
            let speed = calculateSpeed(currentBytes: bytesWritten, phase: phase, download: download)
            activeDownloads[index].audioDownloadSpeed = speed

        case .caption:
            activeDownloads[index].captionTotalBytes = totalBytes
            activeDownloads[index].captionDownloadedBytes = bytesWritten
            if totalBytes > 0 {
                activeDownloads[index].captionProgress = Double(bytesWritten) / Double(totalBytes)
            }
            // Speed calculation for caption - use separate tracking
            let speed = calculateSpeed(currentBytes: bytesWritten, phase: phase, download: download)
            activeDownloads[index].captionDownloadSpeed = speed

        case .storyboard, .thumbnail, .complete:
            // Storyboard and thumbnail progress are handled separately
            break
        }

        // Calculate combined overall progress
        recalculateOverallProgress(for: index)

        // Update per-video progress dictionary for efficient thumbnail observation.
        // SwiftUI only re-renders views that access this specific video's progress.
        let updatedDownload = activeDownloads[index]
        downloadProgressByVideo[updatedDownload.videoID] = DownloadProgressInfo(
            progress: updatedDownload.progress,
            isIndeterminate: updatedDownload.hasIndeterminateProgress
        )

        // Detect progress reset (indicates download restarted)
        let newProgress = activeDownloads[index].progress
        if previousProgress > 0.5 && newProgress < 0.1 {
            LoggingService.shared.logDownload(
                "[Downloads] Progress reset: \(download.videoID.id)",
                details: "Was: \(Int(previousProgress * 100))%, Now: \(Int(newProgress * 100))%, Phase: \(phase), bytesWritten: \(bytesWritten), totalBytes: \(totalBytes)"
            )
        }
    }

    /// Calculate speed for a stream phase (simplified, updates every call)
    func calculateSpeed(currentBytes: Int64, phase: DownloadPhase, download: Download) -> Int64 {
        // For audio/caption, we use a simplified speed calculation
        // since they run in parallel with video
        let previousBytes: Int64
        switch phase {
        case .audio:
            previousBytes = download.audioTotalBytes > 0 ? Int64(download.audioProgress * Double(download.audioTotalBytes)) : 0
        case .caption:
            previousBytes = download.captionTotalBytes > 0 ? Int64(download.captionProgress * Double(download.captionTotalBytes)) : 0
        default:
            return 0
        }

        // Approximate speed based on progress difference (rough estimate)
        let delta = currentBytes - previousBytes
        return max(0, delta * 2) // Multiply by 2 since updates happen ~every 0.5s
    }

    /// Recalculate overall progress from all phases
    func recalculateOverallProgress(for index: Int) {
        let download = activeDownloads[index]
        let hasAudio = download.audioStreamURL != nil
        let hasCaption = download.captionURL != nil
        let hasStoryboard = download.storyboard != nil

        // Weights: video ~79%, audio ~19%, caption ~1%, storyboard ~1%
        let storyboardWeight: Double = hasStoryboard ? 0.01 : 0.0
        let captionWeight: Double = hasCaption ? 0.01 : 0.0
        let audioWeight: Double = hasAudio ? 0.19 : 0.0
        let videoWeight: Double = 1.0 - audioWeight - captionWeight - storyboardWeight

        var overallProgress = download.videoProgress * videoWeight

        if hasAudio {
            overallProgress += download.audioProgress * audioWeight
        }

        if hasCaption {
            overallProgress += download.captionProgress * captionWeight
        }

        if hasStoryboard {
            overallProgress += download.storyboardProgress * storyboardWeight
        }

        activeDownloads[index].progress = min(overallProgress, 0.99) // Cap at 99% until truly complete
    }

    // MARK: - Completion Handling

    /// Result of file operations performed on background thread
    private struct FileOperationResult {
        let success: Bool
        let fileName: String?
        let fileSize: Int64
        let error: Error?
        let errorMessage: String?
        let contentPreview: String?
    }

    func handleDownloadCompletion(downloadID: UUID, phase: DownloadPhase, location: URL, expectedBytes: Int64 = 0) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        let download = activeDownloads[index]
        let minSize = phase == .caption ? Int64(10) : minimumValidFileSize

        // Get expected bytes - use header value if available, otherwise use tracked value from progress
        let effectiveExpectedBytes: Int64
        if expectedBytes > 0 {
            effectiveExpectedBytes = expectedBytes
        } else {
            switch phase {
            case .video: effectiveExpectedBytes = download.videoTotalBytes
            case .audio: effectiveExpectedBytes = download.audioTotalBytes
            case .caption: effectiveExpectedBytes = download.captionTotalBytes
            default: effectiveExpectedBytes = 0
            }
        }

        // Generate filename based on phase (pure computation, safe on main thread)
        let sanitizedVideoID = download.videoID.videoID
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        let fileName: String
        switch phase {
        case .video:
            let fileExtension = download.formatID.isEmpty ? "mp4" : download.formatID
            fileName = "\(sanitizedVideoID)_\(download.quality).\(fileExtension)"
        case .audio:
            let audioExt = download.audioStreamURL?.pathExtension.isEmpty == false
                ? download.audioStreamURL!.pathExtension
                : "m4a"
            let langSuffix = download.audioLanguage.map { "_\($0)" } ?? ""
            fileName = "\(sanitizedVideoID)_audio\(langSuffix).\(audioExt)"
        case .caption:
            let langSuffix = download.captionLanguage ?? "unknown"
            let captionExt = download.captionURL?.pathExtension.isEmpty == false
                ? download.captionURL!.pathExtension
                : "vtt"
            fileName = "\(sanitizedVideoID)_\(langSuffix).\(captionExt)"
        case .storyboard, .thumbnail, .complete:
            return
        }

        let destinationURL = downloadsDirectory().appendingPathComponent(fileName)
        let videoID = download.videoID.id

        // Build URL string for error logging
        let urlString: String
        switch phase {
        case .video: urlString = download.streamURL.absoluteString
        case .audio: urlString = download.audioStreamURL?.absoluteString ?? "none"
        case .caption: urlString = download.captionURL?.absoluteString ?? "none"
        case .storyboard, .thumbnail, .complete: urlString = "n/a"
        }

        // Move ALL file operations to background thread
        Task.detached { [weak self] in
            // Capture self at start of closure to satisfy Swift 6 concurrency
            let manager = self
            let fm = FileManager.default
            var result: FileOperationResult

            do {
                // Check file size
                let attrs = try fm.attributesOfItem(atPath: location.path)
                let downloadedSize = attrs[.size] as? Int64 ?? 0

                if downloadedSize < minSize {
                    // Read small preview for error logging (max 1KB, only for small error files)
                    var contentPreview: String?
                    if downloadedSize < 2048 {
                        if let data = try? Data(contentsOf: location, options: .mappedIfSafe),
                           let preview = String(data: data.prefix(300), encoding: .utf8) {
                            contentPreview = preview.replacingOccurrences(of: "\n", with: " ").prefix(200).description
                        }
                    }

                    try? fm.removeItem(at: location)
                    result = FileOperationResult(
                        success: false,
                        fileName: nil,
                        fileSize: 0,
                        error: DownloadError.downloadFailed("Downloaded file is empty or corrupted (\(downloadedSize) bytes)"),
                        errorMessage: "Got \(downloadedSize) bytes, expected >= \(minSize)",
                        contentPreview: contentPreview
                    )
                } else if effectiveExpectedBytes > 0 {
                    // Validate downloaded size against expected size
                    // If we received less than 90% of expected bytes, the download is incomplete
                    let minimumAcceptableRatio: Double = 0.90
                    let actualRatio = Double(downloadedSize) / Double(effectiveExpectedBytes)

                    if actualRatio < minimumAcceptableRatio {
                        // Download is incomplete - treat as error for auto-retry
                        let percentReceived = Int(actualRatio * 100)
                        try? fm.removeItem(at: location)
                        result = FileOperationResult(
                            success: false,
                            fileName: nil,
                            fileSize: 0,
                            error: DownloadError.downloadFailed("Download incomplete: received \(percentReceived)% of expected data"),
                            errorMessage: "Got \(downloadedSize) bytes, expected \(effectiveExpectedBytes) bytes (\(percentReceived)%)",
                            contentPreview: nil
                        )
                    } else {
                        // Downloaded size is within acceptable range
                        // Remove existing file if present
                        if fm.fileExists(atPath: destinationURL.path) {
                            try fm.removeItem(at: destinationURL)
                        }

                        try fm.moveItem(at: location, to: destinationURL)

                        // Get final file size
                        let finalAttrs = try fm.attributesOfItem(atPath: destinationURL.path)
                        let finalSize = finalAttrs[.size] as? Int64 ?? 0

                        result = FileOperationResult(
                            success: true,
                            fileName: fileName,
                            fileSize: finalSize,
                            error: nil,
                            errorMessage: nil,
                            contentPreview: nil
                        )
                    }
                } else {
                    // Remove existing file if present
                    if fm.fileExists(atPath: destinationURL.path) {
                        try fm.removeItem(at: destinationURL)
                    }

                    try fm.moveItem(at: location, to: destinationURL)

                    // Get final file size
                    let finalAttrs = try fm.attributesOfItem(atPath: destinationURL.path)
                    let finalSize = finalAttrs[.size] as? Int64 ?? 0

                    result = FileOperationResult(
                        success: true,
                        fileName: fileName,
                        fileSize: finalSize,
                        error: nil,
                        errorMessage: nil,
                        contentPreview: nil
                    )
                }
            } catch {
                result = FileOperationResult(
                    success: false,
                    fileName: nil,
                    fileSize: 0,
                    error: error,
                    errorMessage: error.localizedDescription,
                    contentPreview: nil
                )
            }

            // Capture result before entering MainActor to satisfy Swift 6 concurrency
            let finalResult = result

            // Update state on main thread - guard self before MainActor.run for Swift 6
            guard let manager else { return }
            await MainActor.run {
                manager.handleFileOperationResult(
                    result: finalResult,
                    downloadID: downloadID,
                    phase: phase,
                    videoID: videoID,
                    fileName: fileName,
                    urlString: urlString
                )
            }
        }
    }

    /// Handle the result of background file operations (runs on main thread)
    private func handleFileOperationResult(
        result: FileOperationResult,
        downloadID: UUID,
        phase: DownloadPhase,
        videoID: String,
        fileName: String,
        urlString: String
    ) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        if result.success, let savedFileName = result.fileName {
            // Update the appropriate path and progress based on phase
            switch phase {
            case .video:
                activeDownloads[index].localVideoPath = savedFileName
                activeDownloads[index].resumeData = nil
                activeDownloads[index].videoProgress = 1.0
                activeDownloads[index].videoTotalBytes = result.fileSize
                videoTasks.removeValue(forKey: downloadID)
                LoggingService.shared.logDownload("Video saved: \(videoID)", details: savedFileName)

            case .audio:
                activeDownloads[index].localAudioPath = savedFileName
                activeDownloads[index].audioResumeData = nil
                activeDownloads[index].audioProgress = 1.0
                activeDownloads[index].audioTotalBytes = result.fileSize
                audioTasks.removeValue(forKey: downloadID)
                LoggingService.shared.logDownload("Audio saved: \(videoID)", details: savedFileName)

            case .caption:
                activeDownloads[index].localCaptionPath = savedFileName
                activeDownloads[index].captionProgress = 1.0
                captionTasks.removeValue(forKey: downloadID)
                LoggingService.shared.logDownload("Caption saved: \(videoID)", details: savedFileName)

            case .storyboard, .thumbnail, .complete:
                break
            }

            recalculateOverallProgress(for: index)
            saveDownloads()

            Task {
                await checkAndCompleteDownload(downloadID: downloadID)
            }
        } else {
            // Handle error
            if let errorMessage = result.errorMessage {
                // Determine if this is an incomplete download or a corrupt/small file
                let isIncompleteDownload = errorMessage.contains("expected") && errorMessage.contains("%")
                let logCategory = isIncompleteDownload ? "Download incomplete" : "File too small"
                LoggingService.shared.logDownloadError(
                    "[Downloads] \(logCategory) (\(phase)): \(videoID)",
                    error: DownloadError.downloadFailed(errorMessage)
                )
            }
            LoggingService.shared.logDownload(
                "[Downloads] Failed URL (\(phase))",
                details: String(urlString.prefix(150))
            )
            if let preview = result.contentPreview {
                LoggingService.shared.logDownloadError("[Downloads] Content preview: \(preview)")
            }

            handleDownloadError(
                downloadID: downloadID,
                phase: phase,
                error: result.error ?? DownloadError.downloadFailed("Unknown error")
            )
        }
    }

    /// Check if all required phases are complete and finalize the download
    func checkAndCompleteDownload(downloadID: UUID) async {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        let download = activeDownloads[index]

        // Check if video is complete
        let videoComplete = download.localVideoPath != nil

        // Check if audio is complete (or not needed)
        let audioComplete = download.audioStreamURL == nil || download.localAudioPath != nil

        // Check if caption is complete (or not needed, or skipped due to error)
        let captionComplete = download.captionURL == nil ||
                              download.localCaptionPath != nil ||
                              download.captionProgress >= 1.0

        // Check if storyboard is complete (or not needed, or marked complete via progress)
        let storyboardComplete = download.storyboard == nil || download.storyboardProgress >= 1.0

        // If video, audio, caption, and storyboard are complete, start thumbnail download
        // Thumbnail download is best-effort and won't block completion
        if videoComplete && audioComplete && captionComplete && storyboardComplete {
            // Check if thumbnail phase needs to be started
            if download.downloadPhase != .thumbnail && download.downloadPhase != .complete {
                // Start thumbnail download (will call checkAndCompleteDownload again when done)
                startThumbnailDownload(downloadID: downloadID)
                return
            }

            // Thumbnail phase is complete (either finished or was started and callback returned)
            if download.downloadPhase == .thumbnail {
                // Still downloading thumbnails, wait for finalizeThumbnailDownload to call us back
                return
            }

            // All phases complete
            await completeMultiFileDownload(downloadID: downloadID)
        }
    }

    /// Complete a multi-file download after all phases are done
    func completeMultiFileDownload(downloadID: UUID) async {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        var download = activeDownloads[index]
        let baseDir = downloadsDirectory()

        // Capture file paths for background calculation
        let videoPath = download.localVideoPath
        let audioPath = download.localAudioPath
        let captionPath = download.localCaptionPath
        let storyboardPath = download.localStoryboardPath
        let thumbnailPath = download.localThumbnailPath
        let channelThumbnailPath = download.localChannelThumbnailPath

        // Calculate total bytes on background thread to avoid blocking UI
        let totalBytes = await Task.detached {
            let fm = FileManager.default
            var total: Int64 = 0

            if let videoPath {
                total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(videoPath).path, fileManager: fm)
            }
            if let audioPath {
                total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(audioPath).path, fileManager: fm)
            }
            if let captionPath {
                total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(captionPath).path, fileManager: fm)
            }
            if let storyboardPath {
                total += Self.directorySizeBackground(at: baseDir.appendingPathComponent(storyboardPath), fileManager: fm)
            }
            if let thumbnailPath {
                total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(thumbnailPath).path, fileManager: fm)
            }
            if let channelThumbnailPath {
                total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(channelThumbnailPath).path, fileManager: fm)
            }

            return total
        }.value

        // Check if this was a batch download and remove from tracking
        let wasBatchDownload = batchDownloadIDs.contains(downloadID)
        if wasBatchDownload {
            batchDownloadIDs.remove(downloadID)
        }

        // Update download state on main thread
        download.downloadPhase = .complete
        download.status = .completed
        download.completedAt = Date()
        download.progress = 1.0
        download.resumeData = nil
        download.audioResumeData = nil
        download.retryCount = 0
        download.totalBytes = totalBytes
        download.downloadedBytes = totalBytes

        // Move to completed
        activeDownloads.remove(at: index)
        completedDownloads.insert(download, at: 0)

        // Update cached Sets
        downloadingVideoIDs.remove(download.videoID)
        downloadedVideoIDs.insert(download.videoID)
        downloadProgressByVideo.removeValue(forKey: download.videoID)

        // Clean up any remaining task references (should already be removed)
        videoTasks.removeValue(forKey: downloadID)
        audioTasks.removeValue(forKey: downloadID)
        captionTasks.removeValue(forKey: downloadID)
        storyboardTasks.removeValue(forKey: downloadID)
        thumbnailTasks.removeValue(forKey: downloadID)

        var details = "Video: \(download.localVideoPath ?? "none")"
        if download.localAudioPath != nil { details += ", Audio: \(download.localAudioPath!)" }
        if download.localCaptionPath != nil { details += ", Caption: \(download.localCaptionPath!)" }
        if download.localStoryboardPath != nil { details += ", Storyboard: \(download.localStoryboardPath!)" }
        if download.localThumbnailPath != nil { details += ", Thumbnail: \(download.localThumbnailPath!)" }
        LoggingService.shared.logDownload("Completed: \(download.videoID.id)", details: details)

        // Only show individual toast for non-batch downloads
        if !wasBatchDownload {
            if download.warnings.isEmpty {
                toastManager?.show(
                    category: .download,
                    title: String(localized: "toast.download.completed.title"),
                    subtitle: download.title,
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    autoDismissDelay: 3.0
                )
            } else {
                // Partial success toast with warning
                toastManager?.show(
                    category: .download,
                    title: String(localized: "toast.download.completedWithWarnings.title"),
                    subtitle: download.title,
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    autoDismissDelay: 4.0
                )
            }
        }

        saveDownloadsImmediately()

        await calculateStorageUsed()
        await startNextDownloadIfNeeded()
    }

    // MARK: - Error Handling

    func handleDownloadError(downloadID: UUID, phase: DownloadPhase, error: Error) {
        guard let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) else {
            return
        }

        let download = activeDownloads[index]

        // Remove task for this phase
        switch phase {
        case .video:
            videoTasks.removeValue(forKey: downloadID)
        case .audio:
            audioTasks.removeValue(forKey: downloadID)
        case .caption:
            captionTasks.removeValue(forKey: downloadID)
        case .storyboard, .thumbnail, .complete:
            break
        }

        // Check if we should retry
        if download.retryCount < maxRetryAttempts {
            activeDownloads[index].retryCount += 1

            // Clear resume data for the failed phase
            switch phase {
            case .video:
                activeDownloads[index].resumeData = nil
            case .audio:
                activeDownloads[index].audioResumeData = nil
            case .caption, .storyboard, .thumbnail, .complete:
                break
            }

            // Build URL string for logging
            let retryUrlString: String
            switch phase {
            case .video: retryUrlString = String(download.streamURL.absoluteString.prefix(100))
            case .audio: retryUrlString = String((download.audioStreamURL?.absoluteString ?? "none").prefix(100))
            case .caption: retryUrlString = String((download.captionURL?.absoluteString ?? "none").prefix(100))
            case .storyboard, .thumbnail, .complete: retryUrlString = "n/a"
            }
            let delay = retryDelays[min(activeDownloads[index].retryCount - 1, retryDelays.count - 1)]
            LoggingService.shared.logDownload(
                "[Downloads] Retry \(activeDownloads[index].retryCount)/\(maxRetryAttempts + 1) (\(phase)): \(download.videoID.id)",
                details: "Error: \(error.localizedDescription), retrying in \(Int(delay))s"
            )
            LoggingService.shared.logDownload(
                "[Downloads] Retry URL",
                details: retryUrlString
            )

            saveDownloads()

            // Schedule retry with delay - only retry the failed phase
            Task {
                try? await Task.sleep(for: .seconds(delay))

                // Verify download still exists and needs retry
                guard let currentIndex = activeDownloads.firstIndex(where: { $0.id == downloadID }),
                      activeDownloads[currentIndex].status == .downloading else {
                    return
                }

                let currentDownload = activeDownloads[currentIndex]

                // Retry only the failed phase
                switch phase {
                case .video:
                    startStreamDownload(
                        downloadID: downloadID,
                        url: currentDownload.streamURL,
                        phase: .video,
                        resumeData: nil,
                        httpHeaders: currentDownload.httpHeaders
                    )
                case .audio:
                    if let audioURL = currentDownload.audioStreamURL {
                        startStreamDownload(
                            downloadID: downloadID,
                            url: audioURL,
                            phase: .audio,
                            resumeData: nil,
                            httpHeaders: currentDownload.httpHeaders
                        )
                    }
                case .caption:
                    if let captionURL = currentDownload.captionURL {
                        startStreamDownload(
                            downloadID: downloadID,
                            url: captionURL,
                            phase: .caption,
                            resumeData: nil,
                            httpHeaders: currentDownload.httpHeaders
                        )
                    }
                case .storyboard:
                    // Storyboard retry - restart the storyboard download task
                    startStoryboardDownload(downloadID: downloadID)
                case .thumbnail:
                    // Thumbnail retry - restart the thumbnail download task
                    startThumbnailDownload(downloadID: downloadID)
                case .complete:
                    break
                }
            }
        } else {
            // Max retries exceeded
            switch phase {
            case .video, .audio:
                // Critical phases - fail the entire download
                // Remove from batch tracking if this was a batch download
                batchDownloadIDs.remove(downloadID)

                // Cancel other ongoing tasks for this download
                if let task = videoTasks[downloadID] {
                    task.cancel()
                    videoTasks.removeValue(forKey: downloadID)
                }
                if let task = audioTasks[downloadID] {
                    task.cancel()
                    audioTasks.removeValue(forKey: downloadID)
                }
                if let task = captionTasks[downloadID] {
                    task.cancel()
                    captionTasks.removeValue(forKey: downloadID)
                }

                activeDownloads[index].status = .failed
                activeDownloads[index].error = "\(phase.rawValue): \(error.localizedDescription)"

                LoggingService.shared.logDownloadError(
                    "Failed after \(maxRetryAttempts) retries (\(phase)): \(download.videoID.id)",
                    error: error
                )
                saveDownloads()

                Task {
                    await startNextDownloadIfNeeded()
                }

            case .caption:
                // Non-critical phase - mark as skipped and continue
                activeDownloads[index].captionProgress = 1.0 // Mark complete (skipped)
                activeDownloads[index].warnings.append("Subtitles failed to download")
                captionTasks.removeValue(forKey: downloadID)
                LoggingService.shared.logDownload(
                    "Caption download failed (non-fatal): \(download.videoID.id)",
                    details: "Error: \(error.localizedDescription)"
                )
                saveDownloads()
                Task {
                    await checkAndCompleteDownload(downloadID: downloadID)
                }

            case .storyboard, .thumbnail, .complete:
                // Already handled gracefully elsewhere
                break
            }
        }
    }
}

#endif
