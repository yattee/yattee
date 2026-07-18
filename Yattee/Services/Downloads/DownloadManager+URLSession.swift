//
//  DownloadManager+URLSession.swift
//  Yattee
//
//  URLSessionDownloadDelegate conformance for DownloadManager.
//

import Foundation

#if !os(tvOS)

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    /// Parse task description to extract downloadID and phase
    /// Format: "UUID:phase" e.g., "550e8400-e29b-41d4-a716-446655440000:video"
    private nonisolated func parseTaskDescription(_ description: String?) -> (downloadID: UUID, phase: DownloadPhase)? {
        guard let description else { return nil }
        let parts = description.split(separator: ":")
        guard parts.count == 2,
              let uuid = UUID(uuidString: String(parts[0])),
              let phase = DownloadPhase(rawValue: String(parts[1])) else {
            // Fallback: try parsing as just UUID for backward compatibility
            if let uuid = UUID(uuidString: description) {
                return (uuid, .video)
            }
            return nil
        }
        return (uuid, phase)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Try task ID storage first, then fallback to task description
        let taskInfo = getTaskInfo(forTask: downloadTask.taskIdentifier) ??
                       parseTaskDescription(downloadTask.taskDescription)

        guard let taskInfo else {
            Task { @MainActor in
                LoggingService.shared.logDownloadError("Download completed but no download ID found for task \(downloadTask.taskIdentifier)")
            }
            return
        }

        // Log file size at completion with expected size info
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        let expectedSizeFromCountBytes = downloadTask.countOfBytesExpectedToReceive
        Task { @MainActor in
            var details = "taskID: \(downloadTask.taskIdentifier), fileSize: \(fileSize) bytes"
            if expectedSizeFromCountBytes > 0 && expectedSizeFromCountBytes != NSURLSessionTransferSizeUnknown {
                let ratio = expectedSizeFromCountBytes > 0 ? Double(fileSize) / Double(expectedSizeFromCountBytes) * 100 : 0
                details += ", expected: \(expectedSizeFromCountBytes) bytes (\(Int(ratio))%)"
            }
            LoggingService.shared.logDownload(
                "[Downloads] didFinishDownloadingTo (\(taskInfo.phase))",
                details: details
            )
        }

        // Extract expected content length from response headers
        // Check both Content-Length and X-Expected-Content-Length (used by Yattee Server)
        var expectedBytes: Int64 = 0
        if let httpResponse = downloadTask.response as? HTTPURLResponse {
            let statusCode = httpResponse.statusCode
            Task { @MainActor in
                LoggingService.shared.logDownload(
                    "[Downloads] HTTP \(statusCode) (\(taskInfo.phase))",
                    details: "URL: \(httpResponse.url?.host ?? "unknown")"
                )
            }

            // Check for non-success status codes
            if statusCode < 200 || statusCode >= 300 {
                Task { @MainActor in
                    LoggingService.shared.logDownloadError(
                        "[Downloads] Server error HTTP \(statusCode) (\(taskInfo.phase))"
                    )
                    self.handleDownloadError(
                        downloadID: taskInfo.downloadID,
                        phase: taskInfo.phase,
                        error: DownloadError.downloadFailed("Server returned HTTP \(statusCode)")
                    )
                }
                return
            }

            // Extract expected size from headers
            // X-Expected-Content-Length is used by Yattee Server when Content-Length is unavailable
            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
               let size = Int64(contentLength), size > 0 {
                expectedBytes = size
            } else if let expectedSize = httpResponse.value(forHTTPHeaderField: "X-Expected-Content-Length"),
                      let size = Int64(expectedSize), size > 0 {
                expectedBytes = size
            }
        }

        // Copy file to temp location since the original will be deleted
        let originalExtension = location.pathExtension.isEmpty ? "tmp" : location.pathExtension
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + originalExtension)

        do {
            try FileManager.default.copyItem(at: location, to: tempURL)
            let capturedExpectedBytes = expectedBytes
            Task { @MainActor in
                self.handleDownloadCompletion(downloadID: taskInfo.downloadID, phase: taskInfo.phase, location: tempURL, expectedBytes: capturedExpectedBytes)
            }
        } catch {
            Task { @MainActor in
                LoggingService.shared.logDownloadError("Failed to copy downloaded file", error: error)
                self.handleDownloadError(downloadID: taskInfo.downloadID, phase: taskInfo.phase, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskInfo = getTaskInfo(forTask: downloadTask.taskIdentifier) ??
                       parseTaskDescription(downloadTask.taskDescription)

        guard let taskInfo else { return }

        // EARLY THROTTLE: Skip ALL processing if update is too soon (saves CPU)
        // This check must be FIRST to avoid unnecessary work on 100s of callbacks/sec
        let now = Date()
        let lastUpdate = lastProgressUpdateStorage.read { $0[taskInfo.downloadID] } ?? .distantPast
        guard now.timeIntervalSince(lastUpdate) >= 0.3 else { return }
        lastProgressUpdateStorage.write { $0[taskInfo.downloadID] = now }

        // Only process updates that pass the throttle check
        let taskID = downloadTask.taskIdentifier
        let prevBytes = previousBytesStorage.read { $0[taskID] } ?? 0
        if prevBytes > totalBytesWritten + 100_000 {
            // Progress went backwards significantly (reset detected)
            Task { @MainActor in
                LoggingService.shared.logDownload(
                    "[Downloads] URLSession progress reset detected",
                    details: "taskID: \(taskID), prev: \(prevBytes), now: \(totalBytesWritten)"
                )
            }
        }
        previousBytesStorage.write { $0[taskID] = totalBytesWritten }

        // Determine total bytes - use X-Expected-Content-Length header if Content-Length is unknown
        let effectiveTotalBytes: Int64
        if totalBytesExpectedToWrite == NSURLSessionTransferSizeUnknown,
           let response = downloadTask.response as? HTTPURLResponse,
           let expectedSize = response.value(forHTTPHeaderField: "X-Expected-Content-Length"),
           let size = Int64(expectedSize) {
            effectiveTotalBytes = size
        } else {
            effectiveTotalBytes = totalBytesExpectedToWrite
        }

        Task { @MainActor in
            self.handleDownloadProgress(
                downloadID: taskInfo.downloadID,
                phase: taskInfo.phase,
                bytesWritten: totalBytesWritten,
                totalBytes: effectiveTotalBytes
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            let taskInfo = getTaskInfo(forTask: task.taskIdentifier) ??
                           parseTaskDescription(task.taskDescription)

            guard let taskInfo else {
                Task { @MainActor in
                    LoggingService.shared.logDownloadError("Download task failed with error but no download ID found")
                }
                return
            }

            // Check if this was a cancellation with resume data
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                Task { @MainActor in
                    LoggingService.shared.logDownload(
                        "[Downloads] Task cancelled (\(taskInfo.phase))",
                        details: "taskID: \(task.taskIdentifier)"
                    )
                }
                return
            }

            Task { @MainActor in
                LoggingService.shared.logDownloadError("Download task failed (\(taskInfo.phase))", error: error)
                self.handleDownloadError(downloadID: taskInfo.downloadID, phase: taskInfo.phase, error: error)
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // Called when all background tasks are complete
        // Could be used to update UI or show notification
    }
}

#endif
