//
//  DownloadManager+Persistence.swift
//  Yattee
//
//  JSON persistence and diagnostic helpers for DownloadManager.
//

import Foundation

#if !os(tvOS)

extension DownloadManager {
    // MARK: - Persistence

    /// Debounced save - waits 1 second before actually saving to reduce frequent encoding.
    /// Multiple rapid calls will cancel previous pending saves.
    func saveDownloads() {
        // Cancel any pending save
        saveTask?.cancel()

        // Capture current state for saving
        let activeData = activeDownloads
        let completedData = completedDownloads

        saveTask = Task {
            // Wait 1 second before actually saving (debounce)
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            // Perform JSON encoding on background thread
            await Task.detached {
                let encoder = JSONEncoder()

                do {
                    let active = try encoder.encode(activeData)
                    UserDefaults.standard.set(active, forKey: "activeDownloads")
                } catch {
                    LoggingService.shared.logDownloadError("Failed to save active downloads", error: error)
                }

                do {
                    let completed = try encoder.encode(completedData)
                    UserDefaults.standard.set(completed, forKey: "completedDownloads")
                } catch {
                    LoggingService.shared.logDownloadError("Failed to save completed downloads", error: error)
                }
            }.value
        }
    }

    /// Immediate save without debouncing - use for critical state changes.
    func saveDownloadsImmediately() {
        saveTask?.cancel()

        let encoder = JSONEncoder()

        do {
            let activeData = try encoder.encode(activeDownloads)
            UserDefaults.standard.set(activeData, forKey: "activeDownloads")
        } catch {
            LoggingService.shared.logDownloadError("Failed to save active downloads", error: error)
        }

        do {
            let completedData = try encoder.encode(completedDownloads)
            UserDefaults.standard.set(completedData, forKey: "completedDownloads")
        } catch {
            LoggingService.shared.logDownloadError("Failed to save completed downloads", error: error)
        }
    }

    func loadDownloads() {
        let decoder = JSONDecoder()
        
        // ==== ACTIVE DOWNLOADS ====
        if let activeData = UserDefaults.standard.data(forKey: "activeDownloads") {
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] Loading active downloads",
                details: "Size: \(activeData.count) bytes"
            )
            
            // Preview first 100 characters only
            if let preview = String(data: activeData.prefix(100), encoding: .utf8) {
                LoggingService.shared.logDownload(
                    "[DOWNLOADS DIAGNOSTIC] Data preview",
                    details: preview + "..."
                )
            }
            
            do {
                activeDownloads = try decoder.decode([Download].self, from: activeData)
                LoggingService.shared.logDownload(
                    "[DOWNLOADS DIAGNOSTIC] ✅ Loaded active downloads: \(activeDownloads.count)"
                )
            } catch let decodingError as DecodingError {
                let diagnostics = diagnoseDecodingError(decodingError, dataSize: activeData.count)
                LoggingService.shared.logDownloadError(
                    "[DOWNLOADS DIAGNOSTIC] ❌ DecodingError in active downloads",
                    error: decodingError
                )
                LoggingService.shared.logDownload(
                    "[DOWNLOADS DIAGNOSTIC] Error details",
                    details: diagnostics
                )
                inspectRawJSON(activeData, key: "activeDownloads")
            } catch {
                LoggingService.shared.logDownloadError(
                    "[DOWNLOADS DIAGNOSTIC] ❌ Unexpected error in active downloads",
                    error: error
                )
            }
        } else {
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] No active downloads in UserDefaults"
            )
        }
        
        // ==== COMPLETED DOWNLOADS ====
        if let completedData = UserDefaults.standard.data(forKey: "completedDownloads") {
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] Loading completed downloads",
                details: "Size: \(completedData.count) bytes"
            )
            
            // Preview first 100 characters only
            if let preview = String(data: completedData.prefix(100), encoding: .utf8) {
                LoggingService.shared.logDownload(
                    "[DOWNLOADS DIAGNOSTIC] Data preview",
                    details: preview + "..."
                )
            }
            
            do {
                completedDownloads = try decoder.decode([Download].self, from: completedData)
                LoggingService.shared.logDownload(
                    "[DOWNLOADS DIAGNOSTIC] ✅ Loaded completed downloads: \(completedDownloads.count)"
                )

                // Validate completed downloads have files on disk
                let beforeCount = completedDownloads.count
                completedDownloads.removeAll { download in
                    guard let fileURL = resolveLocalURL(for: download),
                          fileManager.fileExists(atPath: fileURL.path) else {
                        LoggingService.shared.warning(
                            "[Downloads] Removing orphaned record: \(download.videoID) — file missing at \(download.localVideoPath ?? "nil")",
                            category: .downloads
                        )
                        return true
                    }
                    return false
                }
                let removed = beforeCount - completedDownloads.count
                if removed > 0 {
                    LoggingService.shared.warning("[Downloads] Removed \(removed) orphaned download record(s)", category: .downloads)
                    saveDownloadsImmediately()
                }
            } catch let decodingError as DecodingError {
                let diagnostics = diagnoseDecodingError(decodingError, dataSize: completedData.count)
                LoggingService.shared.logDownloadError(
                    "[DOWNLOADS DIAGNOSTIC] ❌ DecodingError in completed downloads",
                    error: decodingError
                )
                LoggingService.shared.logDownload(
                    "[DOWNLOADS DIAGNOSTIC] Error details",
                    details: diagnostics
                )
                inspectRawJSON(completedData, key: "completedDownloads")
            } catch {
                LoggingService.shared.logDownloadError(
                    "[DOWNLOADS DIAGNOSTIC] ❌ Unexpected error in completed downloads",
                    error: error
                )
            }
        } else {
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] No completed downloads in UserDefaults"
            )
        }
        
        // ==== POST-LOAD DIAGNOSTICS ====
        Task {
            await calculateStorageUsed()
            await diagnoseOrphanedFiles()
        }
        
        // Rebuild cached Sets for O(1) lookup
        downloadingVideoIDs = Set(activeDownloads.map { $0.videoID })
        downloadedVideoIDs = Set(completedDownloads.map { $0.videoID })

        // Initialize per-video progress dictionary for active downloads
        for download in activeDownloads {
            downloadProgressByVideo[download.videoID] = DownloadProgressInfo(
                progress: download.progress,
                isIndeterminate: download.hasIndeterminateProgress
            )
        }
    }

    // MARK: - Diagnostic Helpers

    /// Diagnoses a decoding error and returns detailed diagnostic information.
    func diagnoseDecodingError(_ error: DecodingError, dataSize: Int) -> String {
        var diagnostics: [String] = []
        
        switch error {
        case .keyNotFound(let key, let context):
            diagnostics.append("Missing key: '\(key.stringValue)'")
            if !context.codingPath.isEmpty {
                diagnostics.append("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " → "))")
            }
            diagnostics.append("Description: \(context.debugDescription)")
            
        case .typeMismatch(let type, let context):
            diagnostics.append("Type mismatch: expected \(type)")
            if !context.codingPath.isEmpty {
                diagnostics.append("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " → "))")
            }
            diagnostics.append("Description: \(context.debugDescription)")
            
        case .valueNotFound(let type, let context):
            diagnostics.append("Value not found: expected \(type)")
            if !context.codingPath.isEmpty {
                diagnostics.append("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " → "))")
            }
            diagnostics.append("Description: \(context.debugDescription)")
            
        case .dataCorrupted(let context):
            diagnostics.append("Data corrupted")
            if !context.codingPath.isEmpty {
                diagnostics.append("Coding path: \(context.codingPath.map { $0.stringValue }.joined(separator: " → "))")
            }
            diagnostics.append("Description: \(context.debugDescription)")
            
        @unknown default:
            diagnostics.append("Unknown decoding error: \(error)")
        }
        
        diagnostics.append("Data size: \(dataSize) bytes")
        
        return diagnostics.joined(separator: "\n")
    }

    /// Inspects raw JSON data to identify missing fields and patterns.
    func inspectRawJSON(_ data: Data, key: String) {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] Failed to parse \(key) as JSON array"
            )
            return
        }
        
        LoggingService.shared.logDownload(
            "[DOWNLOADS DIAGNOSTIC] \(key) contains \(jsonArray.count) items"
        )
        
        // Analyze first item's fields
        if let firstItem = jsonArray.first {
            let fields = firstItem.keys.sorted()
            
            // Only log first 10 fields to save space
            let fieldsPreview = fields.prefix(10).joined(separator: ", ") + 
                               (fields.count > 10 ? "... (total: \(fields.count) fields)" : "")
            
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] First item fields",
                details: fieldsPreview
            )
            
            // Check for storyboard-related fields
            let hasStoryboard = fields.contains("storyboard")
            let hasStoryboardPath = fields.contains("localStoryboardPath")
            let hasStoryboardProgress = fields.contains("storyboardProgress")
            let hasStoryboardTotalBytes = fields.contains("storyboardTotalBytes")
            
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] Storyboard fields check",
                details: """
                storyboard: \(hasStoryboard)
                localStoryboardPath: \(hasStoryboardPath)
                storyboardProgress: \(hasStoryboardProgress)
                storyboardTotalBytes: \(hasStoryboardTotalBytes)
                """
            )
        }
        
        // Check if all items have same fields (pattern detection)
        if jsonArray.count > 1 {
            let allFieldSets = jsonArray.map { Set($0.keys) }
            let allSame = allFieldSets.allSatisfy { $0 == allFieldSets[0] }
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] All \(jsonArray.count) items have identical field structure: \(allSame)"
            )
        }
    }

    /// Diagnoses orphaned files by comparing disk storage with loaded downloads.
    func diagnoseOrphanedFiles() async {
        do {
            let downloadsDir = downloadsDirectory()
            let contents = try fileManager.contentsOfDirectory(
                at: downloadsDir,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            
            // Count video files (*.mp4, *.mkv, etc.)
            let videoFiles = contents.filter { url in
                let ext = url.pathExtension.lowercased()
                return ["mp4", "mkv", "webm", "mov", "m4v"].contains(ext)
            }
            
            // Count directories (might contain separate video/audio)
            let directories = contents.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            
            let totalLoaded = activeDownloads.count + completedDownloads.count
            
            LoggingService.shared.logDownload(
                "[DOWNLOADS DIAGNOSTIC] Orphaned files analysis",
                details: """
                Video files on disk: \(videoFiles.count)
                Directories on disk: \(directories.count)
                Total downloads loaded: \(totalLoaded)
                - Active: \(activeDownloads.count)
                - Completed: \(completedDownloads.count)
                Potential orphans: \(max(0, videoFiles.count + directories.count - totalLoaded))
                Storage used: \(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                """
            )
            
        } catch {
            LoggingService.shared.logDownloadError(
                "[DOWNLOADS DIAGNOSTIC] Failed to diagnose orphaned files",
                error: error
            )
        }
    }
}

#endif
