//
//  DownloadTests.swift
//  YatteeTests
//
//  Tests for the download system.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Download Model Tests

@Suite("Download Model Tests")
struct DownloadModelTests {

    @Test("Download initialization from Video")
    func initialization() {
        let video = makeTestVideo()
        let streamURL = URL(string: "https://example.com/stream.mp4")!
        let download = Download(
            video: video,
            quality: "1080p",
            formatID: "137",
            streamURL: streamURL
        )

        #expect(download.videoID == video.id)
        #expect(download.title == video.title)
        #expect(download.channelName == video.author.name)
        #expect(download.quality == "1080p")
        #expect(download.formatID == "137")
        #expect(download.status == .queued)
        #expect(download.progress == 0)
        #expect(download.priority == .normal)
        #expect(download.autoDelete == false)
    }

    @Test("Download with high priority")
    func highPriority() {
        let video = makeTestVideo()
        let streamURL = URL(string: "https://example.com/stream.mp4")!
        let download = Download(
            video: video,
            quality: "720p",
            formatID: "136",
            streamURL: streamURL,
            priority: .high
        )

        #expect(download.priority == .high)
    }

    @Test("Download with auto-delete enabled")
    func autoDelete() {
        let video = makeTestVideo()
        let streamURL = URL(string: "https://example.com/stream.mp4")!
        let download = Download(
            video: video,
            quality: "720p",
            formatID: "136",
            streamURL: streamURL,
            autoDelete: true
        )

        #expect(download.autoDelete == true)
    }

    private func makeTestVideo() -> Video {
        Video(
            id: .global("testDownload"),
            title: "Test Download Video",
            description: "A video to test downloads",
            author: Author(id: "ch1", name: "Test Channel"),
            duration: 600,
            publishedAt: Date(),
            publishedText: "1 day ago",
            viewCount: 10000,
            likeCount: 500,
            thumbnails: [
                Thumbnail(url: URL(string: "https://example.com/thumb.jpg")!, quality: .high)
            ],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

// MARK: - Download Status Tests

@Suite("Download Status Tests")
struct DownloadStatusTests {

    @Test("Status raw values")
    func rawValues() {
        #expect(DownloadStatus.queued.rawValue == "queued")
        #expect(DownloadStatus.downloading.rawValue == "downloading")
        #expect(DownloadStatus.paused.rawValue == "paused")
        #expect(DownloadStatus.completed.rawValue == "completed")
        #expect(DownloadStatus.failed.rawValue == "failed")
    }

    @Test("Status is Codable")
    func codable() throws {
        for status in [DownloadStatus.queued, .downloading, .paused, .completed, .failed] {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(DownloadStatus.self, from: encoded)
            #expect(status == decoded)
        }
    }
}

// MARK: - Download Priority Tests

@Suite("Download Priority Tests")
struct DownloadPriorityTests {

    @Test("Priority ordering")
    func ordering() {
        #expect(DownloadPriority.low.rawValue < DownloadPriority.normal.rawValue)
        #expect(DownloadPriority.normal.rawValue < DownloadPriority.high.rawValue)
    }

    @Test("Priority is Codable")
    func codable() throws {
        for priority in [DownloadPriority.low, .normal, .high] {
            let encoded = try JSONEncoder().encode(priority)
            let decoded = try JSONDecoder().decode(DownloadPriority.self, from: encoded)
            #expect(priority == decoded)
        }
    }
}

// MARK: - DownloadSortOption Tests

@Suite("DownloadSortOption Tests")
struct DownloadSortOptionTests {

    @Test("All cases exist")
    func allCases() {
        let cases = DownloadSortOption.allCases
        #expect(cases.contains(.name))
        #expect(cases.contains(.downloadDate))
        #expect(cases.contains(.fileSize))
        #expect(cases.count == 3)
    }

    @Test("Display names are not empty")
    func displayNames() {
        for option in DownloadSortOption.allCases {
            #expect(!option.displayName.isEmpty)
        }
    }

    @Test("System images are valid SF Symbols")
    func systemImages() {
        #expect(DownloadSortOption.name.systemImage == "textformat")
        #expect(DownloadSortOption.downloadDate.systemImage == "calendar")
        #expect(DownloadSortOption.fileSize.systemImage == "internaldrive")
    }

    @Test("Is Codable")
    func codable() throws {
        for option in DownloadSortOption.allCases {
            let encoded = try JSONEncoder().encode(option)
            let decoded = try JSONDecoder().decode(DownloadSortOption.self, from: encoded)
            #expect(option == decoded)
        }
    }
}

// MARK: - SortDirection Tests

@Suite("SortDirection Tests")
struct SortDirectionTests {

    @Test("All cases exist")
    func allCases() {
        let cases = SortDirection.allCases
        #expect(cases.contains(.ascending))
        #expect(cases.contains(.descending))
        #expect(cases.count == 2)
    }

    @Test("System images are valid")
    func systemImages() {
        #expect(SortDirection.ascending.systemImage == "arrow.up")
        #expect(SortDirection.descending.systemImage == "arrow.down")
    }

    @Test("Toggle switches direction")
    func toggle() {
        var direction = SortDirection.ascending
        direction.toggle()
        #expect(direction == .descending)
        direction.toggle()
        #expect(direction == .ascending)
    }

    @Test("Is Codable")
    func codable() throws {
        for direction in SortDirection.allCases {
            let encoded = try JSONEncoder().encode(direction)
            let decoded = try JSONDecoder().decode(SortDirection.self, from: encoded)
            #expect(direction == decoded)
        }
    }
}

// MARK: - DownloadSettings Tests

@Suite("DownloadSettings Tests")
@MainActor
struct DownloadSettingsTests {

    @Test("Default sort option is downloadDate")
    func defaultSortOption() {
        // Clear existing defaults
        UserDefaults.standard.removeObject(forKey: "downloads.sortOption")
        let settings = DownloadSettings()
        #expect(settings.sortOption == .downloadDate)
    }

    @Test("Default sort direction is descending")
    func defaultSortDirection() {
        // Clear existing defaults
        UserDefaults.standard.removeObject(forKey: "downloads.sortDirection")
        let settings = DownloadSettings()
        #expect(settings.sortDirection == .descending)
    }

    @Test("Default groupByChannel is false")
    func defaultGroupByChannel() {
        // Clear existing defaults
        UserDefaults.standard.removeObject(forKey: "downloads.groupByChannel")
        let settings = DownloadSettings()
        #expect(settings.groupByChannel == false)
    }

    @Test("Sort option persists")
    func sortOptionPersists() {
        UserDefaults.standard.removeObject(forKey: "downloads.sortOption")
        let settings = DownloadSettings()
        settings.sortOption = .name

        // Create new instance to check persistence
        let settings2 = DownloadSettings()
        #expect(settings2.sortOption == .name)
    }

    @Test("Sort direction persists")
    func sortDirectionPersists() {
        UserDefaults.standard.removeObject(forKey: "downloads.sortDirection")
        let settings = DownloadSettings()
        settings.sortDirection = .ascending

        let settings2 = DownloadSettings()
        #expect(settings2.sortDirection == .ascending)
    }

    @Test("GroupByChannel persists")
    func groupByChannelPersists() {
        UserDefaults.standard.removeObject(forKey: "downloads.groupByChannel")
        let settings = DownloadSettings()
        settings.groupByChannel = true

        let settings2 = DownloadSettings()
        #expect(settings2.groupByChannel == true)
    }
}

// MARK: - Download Error Tests

@Suite("Download Error Tests")
struct DownloadErrorTests {

    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let notSupported = DownloadError.notSupported
        #expect(notSupported.errorDescription?.contains("not supported") == true)

        let alreadyDownloading = DownloadError.alreadyDownloading
        #expect(alreadyDownloading.errorDescription?.contains("already downloading") == true)

        let alreadyDownloaded = DownloadError.alreadyDownloaded
        #expect(alreadyDownloaded.errorDescription?.contains("already been downloaded") == true)

        let noStream = DownloadError.noStreamAvailable
        #expect(noStream.errorDescription?.contains("stream") == true)

        let failed = DownloadError.downloadFailed("Network timeout")
        #expect(failed.errorDescription?.contains("Network timeout") == true)
    }
}

// MARK: - DownloadManager Tests

@Suite("DownloadManager Tests")
@MainActor
struct DownloadManagerTests {

    init() {
        // Clear UserDefaults for clean test state
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")
    }

    @Test("Initial state with clean defaults")
    func initialState() {
        // Clear state before test
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")

        let manager = DownloadManager()

        #expect(manager.activeDownloads.isEmpty)
        #expect(manager.completedDownloads.isEmpty)
        #expect(manager.storageUsed == 0)
        #expect(manager.maxConcurrentDownloads == 2)
    }

    @Test("isDownloaded returns false for unknown video")
    func isDownloadedUnknown() {
        let manager = DownloadManager()
        let videoID = VideoID.global("unknown")

        #expect(manager.isDownloaded(videoID) == false)
    }

    @Test("isDownloading returns false for unknown video")
    func isDownloadingUnknown() {
        let manager = DownloadManager()
        let videoID = VideoID.global("unknown")

        #expect(manager.isDownloading(videoID) == false)
    }

    @Test("download(for:) returns nil for unknown video")
    func downloadForUnknown() {
        let manager = DownloadManager()
        let videoID = VideoID.global("unknown")

        #expect(manager.download(for: videoID) == nil)
    }

    @Test("localURL returns nil for unknown video")
    func localURLUnknown() {
        let manager = DownloadManager()
        let videoID = VideoID.global("unknown")

        #expect(manager.localURL(for: videoID) == nil)
    }

    @Test("Available storage returns non-negative value")
    func availableStorage() {
        let manager = DownloadManager()
        let available = manager.getAvailableStorage()

        #expect(available >= 0)
    }

    #if !os(tvOS)
    @Test("Enqueue prevents duplicate downloads")
    func enqueueDuplicatePrevention() async throws {
        // Clear state before test
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")

        let manager = DownloadManager()
        let video = makeTestVideo(id: "duplicate")
        let streamURL = URL(string: "https://example.com/video.mp4")!

        // First enqueue should succeed
        try await manager.enqueue(video, quality: "720p", formatID: "136", streamURL: streamURL)
        #expect(manager.activeDownloads.count == 1)

        // Second enqueue should throw alreadyDownloading
        do {
            try await manager.enqueue(video, quality: "720p", formatID: "136", streamURL: streamURL)
            Issue.record("Expected alreadyDownloading error")
        } catch DownloadError.alreadyDownloading {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(manager.activeDownloads.count == 1)
    }

    @Test("Cancel removes download from queue")
    func cancelRemovesDownload() async throws {
        // Clear state before test
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")

        let manager = DownloadManager()
        let video = makeTestVideo(id: "toCancel")
        let streamURL = URL(string: "https://example.com/video.mp4")!

        try await manager.enqueue(video, quality: "720p", formatID: "136", streamURL: streamURL)
        #expect(manager.activeDownloads.count == 1)

        let download = manager.activeDownloads.first!
        await manager.cancel(download)

        #expect(manager.activeDownloads.isEmpty)
    }

    @Test("Pause changes status")
    func pauseChangesStatus() async throws {
        // Clear state before test
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")

        let manager = DownloadManager()
        let video = makeTestVideo(id: "toPause")
        let streamURL = URL(string: "https://example.com/video.mp4")!

        try await manager.enqueue(video, quality: "720p", formatID: "136", streamURL: streamURL)
        let download = manager.activeDownloads.first!

        await manager.pause(download)

        let updated = manager.activeDownloads.first
        #expect(updated?.status == .paused)
    }

    @Test("Resume changes status from paused to queued")
    func resumeChangesStatus() async throws {
        // Clear state before test
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")

        let manager = DownloadManager()
        let video = makeTestVideo(id: "toResume")
        let streamURL = URL(string: "https://example.com/video.mp4")!

        try await manager.enqueue(video, quality: "720p", formatID: "136", streamURL: streamURL)
        let download = manager.activeDownloads.first!

        await manager.pause(download)
        #expect(manager.activeDownloads.first?.status == .paused)

        let pausedDownload = manager.activeDownloads.first!
        await manager.resume(pausedDownload)

        #expect(manager.activeDownloads.first?.status == .queued || manager.activeDownloads.first?.status == .downloading)
    }

    @Test("Move in queue reorders downloads")
    func moveInQueue() async throws {
        // Clear state before test
        UserDefaults.standard.removeObject(forKey: "activeDownloads")
        UserDefaults.standard.removeObject(forKey: "completedDownloads")

        let manager = DownloadManager()

        // Enqueue multiple downloads
        for i in 1...3 {
            let video = makeTestVideo(id: "move\(i)")
            let streamURL = URL(string: "https://example.com/video\(i).mp4")!
            try await manager.enqueue(video, quality: "720p", formatID: "136", streamURL: streamURL)
        }

        #expect(manager.activeDownloads.count == 3)

        // Move last to first
        let lastDownload = manager.activeDownloads.last!
        await manager.moveInQueue(lastDownload, to: 0)

        #expect(manager.activeDownloads.first?.videoID.videoID == "move3")
    }
    #endif

    private func makeTestVideo(id: String) -> Video {
        Video(
            id: .global(id),
            title: "Test Video \(id)",
            description: nil,
            author: Author(id: "ch1", name: "Channel"),
            duration: 300,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}
