//
//  DownloadManager+Storage.swift
//  Yattee
//
//  Storage management and orphan detection for DownloadManager.
//

import Foundation

#if !os(tvOS)

extension DownloadManager {
    // MARK: - Storage Management

    /// Calculate total storage used by downloads (file operations run on background thread).
    @discardableResult
    func calculateStorageUsed() async -> Int64 {
        // Capture download paths on main thread
        let downloads = completedDownloads
        let baseDir = downloadsDirectory()

        // Calculate on background thread to avoid blocking UI
        let total = await Task.detached {
            let fm = FileManager.default
            var total: Int64 = 0

            for download in downloads {
                // Count video file
                if let videoPath = download.localVideoPath {
                    total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(videoPath).path, fileManager: fm)
                }
                // Count audio file
                if let audioPath = download.localAudioPath {
                    total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(audioPath).path, fileManager: fm)
                }
                // Count caption file
                if let captionPath = download.localCaptionPath {
                    total += Self.fileSizeBackground(at: baseDir.appendingPathComponent(captionPath).path, fileManager: fm)
                }
                // Count storyboard directory
                if let storyboardPath = download.localStoryboardPath {
                    total += Self.directorySizeBackground(at: baseDir.appendingPathComponent(storyboardPath), fileManager: fm)
                }
            }

            return total
        }.value

        // Update published property on main thread
        storageUsed = total
        return total
    }

    /// Background-safe file size calculation (nonisolated static method)
    nonisolated static func fileSizeBackground(at path: String, fileManager: FileManager) -> Int64 {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            return attrs[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Background-safe directory size calculation (nonisolated static method)
    nonisolated static func directorySizeBackground(at url: URL, fileManager: FileManager) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        var size: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }

    /// Get available storage on device.
    func getAvailableStorage() -> Int64 {
        do {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            let values = try documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage ?? 0
        } catch {
            return 0
        }
    }

    /// Calculate total size of a directory
    func directorySize(at url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        var size: Int64 = 0
        if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    size += Int64(fileSize)
                }
            }
        }
        return size
    }

    // MARK: - Orphan Detection & Cleanup

    /// Represents an orphaned file not tracked by any download record.
    struct OrphanedFile: Identifiable {
        let id = UUID()
        let url: URL
        let fileName: String
        let size: Int64
    }

    /// Scan the downloads directory for orphaned files not tracked by any download record.
    /// Returns a list of orphaned files with their sizes.
    func findOrphanedFiles() -> (orphanedFiles: [OrphanedFile], totalOrphanedSize: Int64, trackedSize: Int64, actualDiskSize: Int64) {
        let downloadsDir = downloadsDirectory()

        // Build set of all tracked file paths
        var trackedPaths = Set<String>()
        var trackedSize: Int64 = 0

        // From completed downloads
        for download in completedDownloads {
            if let videoPath = download.localVideoPath {
                trackedPaths.insert(videoPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(videoPath).path)
            }
            if let audioPath = download.localAudioPath {
                trackedPaths.insert(audioPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(audioPath).path)
            }
            if let captionPath = download.localCaptionPath {
                trackedPaths.insert(captionPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(captionPath).path)
            }
            if let storyboardPath = download.localStoryboardPath {
                trackedPaths.insert(storyboardPath)
                trackedSize += directorySize(at: downloadsDir.appendingPathComponent(storyboardPath))
            }
            if let thumbnailPath = download.localThumbnailPath {
                trackedPaths.insert(thumbnailPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(thumbnailPath).path)
            }
            if let channelThumbnailPath = download.localChannelThumbnailPath {
                trackedPaths.insert(channelThumbnailPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(channelThumbnailPath).path)
            }
        }

        // From active downloads (in progress)
        for download in activeDownloads {
            if let videoPath = download.localVideoPath {
                trackedPaths.insert(videoPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(videoPath).path)
            }
            if let audioPath = download.localAudioPath {
                trackedPaths.insert(audioPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(audioPath).path)
            }
            if let captionPath = download.localCaptionPath {
                trackedPaths.insert(captionPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(captionPath).path)
            }
            if let storyboardPath = download.localStoryboardPath {
                trackedPaths.insert(storyboardPath)
                trackedSize += directorySize(at: downloadsDir.appendingPathComponent(storyboardPath))
            }
            if let thumbnailPath = download.localThumbnailPath {
                trackedPaths.insert(thumbnailPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(thumbnailPath).path)
            }
            if let channelThumbnailPath = download.localChannelThumbnailPath {
                trackedPaths.insert(channelThumbnailPath)
                trackedSize += fileSize(at: downloadsDir.appendingPathComponent(channelThumbnailPath).path)
            }
        }

        // Scan directory for all files and directories
        var orphanedFiles: [OrphanedFile] = []
        var totalOrphanedSize: Int64 = 0
        var actualDiskSize: Int64 = 0

        do {
            let contents = try fileManager.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey])

            for fileURL in contents {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let fileName = fileURL.lastPathComponent
                let isDirectory = resourceValues.isDirectory == true

                let size: Int64
                if isDirectory {
                    size = directorySize(at: fileURL)
                } else {
                    size = Int64(resourceValues.fileSize ?? 0)
                }

                actualDiskSize += size

                if !trackedPaths.contains(fileName) {
                    orphanedFiles.append(OrphanedFile(url: fileURL, fileName: fileName, size: size))
                    totalOrphanedSize += size
                }
            }
        } catch {
            LoggingService.shared.logDownloadError("Failed to scan downloads directory for orphans", error: error)
        }

        return (orphanedFiles, totalOrphanedSize, trackedSize, actualDiskSize)
    }

    /// Log detailed diagnostic information about orphaned files.
    /// Call this to debug storage discrepancy issues.
    func logOrphanDiagnostics() {
        let (orphanedFiles, totalOrphanedSize, trackedSize, actualDiskSize) = findOrphanedFiles()

        LoggingService.shared.logDownload(
            "=== DOWNLOAD STORAGE DIAGNOSTICS ===",
            details: """
            Tracked downloads: \(completedDownloads.count) completed, \(activeDownloads.count) active
            Tracked file size: \(formatBytes(trackedSize))
            Actual disk usage: \(formatBytes(actualDiskSize))
            Orphaned files: \(orphanedFiles.count) (\(formatBytes(totalOrphanedSize)))
            Discrepancy: \(formatBytes(actualDiskSize - trackedSize))
            """
        )

        if !orphanedFiles.isEmpty {
            LoggingService.shared.logDownload("=== ORPHANED FILES ===")
            for file in orphanedFiles.sorted(by: { $0.size > $1.size }) {
                LoggingService.shared.logDownload(
                    "Orphan: \(file.fileName)",
                    details: "Size: \(formatBytes(file.size))"
                )
            }
        }
    }

    /// Delete all orphaned files not tracked by any download record.
    /// Returns the number of files deleted and total bytes freed.
    @discardableResult
    func deleteOrphanedFiles() async -> (deletedCount: Int, bytesFreed: Int64) {
        let (orphanedFiles, _, _, _) = findOrphanedFiles()

        var deletedCount = 0
        var bytesFreed: Int64 = 0

        for file in orphanedFiles {
            do {
                try fileManager.removeItem(at: file.url)
                deletedCount += 1
                bytesFreed += file.size
                LoggingService.shared.logDownload("Deleted orphan: \(file.fileName)", details: "Freed: \(formatBytes(file.size))")
            } catch {
                LoggingService.shared.logDownloadError("Failed to delete orphan: \(file.fileName)", error: error)
            }
        }

        if deletedCount > 0 {
            LoggingService.shared.logDownload(
                "Orphan cleanup complete",
                details: "Deleted \(deletedCount) files, freed \(formatBytes(bytesFreed))"
            )
            await calculateStorageUsed()
        }

        return (deletedCount, bytesFreed)
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#endif
