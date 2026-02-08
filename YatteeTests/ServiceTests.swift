//
//  ServiceTests.swift
//  YatteeTests
//
//  Tests for service layer components including WebDAV client and storage utilities.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Storage Diagnostics Tests

@Suite("StorageDiagnostics Tests")
@MainActor
struct StorageDiagnosticsTests {

    @Test("StorageUsageItem initialization")
    func storageUsageItemInit() {
        let item = StorageUsageItem(
            name: "Downloads",
            path: "/path/to/downloads",
            size: 1024 * 1024 * 500, // 500 MB
            fileCount: 42
        )

        #expect(item.name == "Downloads")
        #expect(item.path == "/path/to/downloads")
        #expect(item.size == 524288000)
        #expect(item.fileCount == 42)
        #expect(!item.id.uuidString.isEmpty)
    }

    @Test("StorageUsageItem is Identifiable")
    func storageUsageItemIdentifiable() {
        let item1 = StorageUsageItem(name: "A", path: "/a", size: 100, fileCount: 1)
        let item2 = StorageUsageItem(name: "A", path: "/a", size: 100, fileCount: 1)

        // Each item should have unique ID even with same content
        #expect(item1.id != item2.id)
    }

    @Test("StorageDiagnostics formatted values")
    func diagnosticsFormattedValues() {
        let diagnostics = StorageDiagnostics(
            items: [],
            totalSize: 1024 * 1024 * 1024, // 1 GB
            documentsSize: 500 * 1024 * 1024,
            cachesSize: 200 * 1024 * 1024,
            appSupportSize: 100 * 1024 * 1024,
            tempSize: 50 * 1024 * 1024,
            otherSize: 150 * 1024 * 1024
        )

        #expect(!diagnostics.formattedTotal.isEmpty)
        #expect(!diagnostics.formattedDocuments.isEmpty)
        #expect(!diagnostics.formattedCaches.isEmpty)
        #expect(!diagnostics.formattedAppSupport.isEmpty)
        #expect(!diagnostics.formattedTemp.isEmpty)
    }

    @Test("StorageDiagnostics with items")
    func diagnosticsWithItems() {
        let items = [
            StorageUsageItem(name: "Downloads", path: "/downloads", size: 300_000_000, fileCount: 10),
            StorageUsageItem(name: "Cache", path: "/cache", size: 100_000_000, fileCount: 50),
            StorageUsageItem(name: "Temp", path: "/temp", size: 50_000_000, fileCount: 5)
        ]

        let diagnostics = StorageDiagnostics(
            items: items,
            totalSize: 450_000_000,
            documentsSize: 300_000_000,
            cachesSize: 100_000_000,
            appSupportSize: 0,
            tempSize: 50_000_000,
            otherSize: 0
        )

        #expect(diagnostics.items.count == 3)
        #expect(diagnostics.totalSize == 450_000_000)
    }

    @Test("scanAppStorage returns valid diagnostics")
    func scanAppStorageReturnsValid() {
        let diagnostics = scanAppStorage()

        #expect(diagnostics.totalSize >= 0)
        #expect(diagnostics.documentsSize >= 0)
        #expect(diagnostics.cachesSize >= 0)
        #expect(!diagnostics.formattedTotal.isEmpty)
    }
}

// MARK: - LockedStorage Tests

@Suite("LockedStorage Tests")
struct LockedStorageTests {

    @Test("LockedStorage read returns value")
    func readReturnsValue() {
        let storage = LockedStorage(42)
        let value = storage.read { $0 }
        #expect(value == 42)
    }

    @Test("LockedStorage write modifies value")
    func writeModifiesValue() {
        let storage = LockedStorage(0)
        storage.write { $0 += 10 }
        let value = storage.read { $0 }
        #expect(value == 10)
    }

    @Test("LockedStorage with string")
    func withString() {
        let storage = LockedStorage("hello")
        storage.write { $0 += " world" }
        let value = storage.read { $0 }
        #expect(value == "hello world")
    }

    @Test("LockedStorage with array")
    func withArray() {
        let storage = LockedStorage<[Int]>([])
        storage.write { $0.append(1) }
        storage.write { $0.append(2) }
        storage.write { $0.append(3) }
        let value = storage.read { $0 }
        #expect(value == [1, 2, 3])
    }

    @Test("LockedStorage read with transformation")
    func readWithTransformation() {
        let storage = LockedStorage([1, 2, 3, 4, 5])
        let sum = storage.read { $0.reduce(0, +) }
        #expect(sum == 15)
    }

    @Test("LockedStorage concurrent access")
    func concurrentAccess() async {
        let storage = LockedStorage(0)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    storage.write { $0 += 1 }
                }
            }
        }

        let finalValue = storage.read { $0 }
        #expect(finalValue == 100)
    }
}

// MARK: - BandwidthTestResult Tests

@Suite("BandwidthTestResult Tests")
struct BandwidthTestResultTests {

    @Test("BandwidthTestResult with write access")
    func bandwidthTestResultWithWrite() {
        let result = BandwidthTestResult(
            hasWriteAccess: true,
            uploadSpeed: 50_000_000, // 50 MB/s
            downloadSpeed: 100_000_000, // 100 MB/s
            testFileSize: 5 * 1024 * 1024, // 5 MB
            warning: nil
        )

        #expect(result.hasWriteAccess == true)
        #expect(result.uploadSpeed == 50_000_000)
        #expect(result.downloadSpeed == 100_000_000)
        #expect(result.testFileSize == 5 * 1024 * 1024)
        #expect(result.warning == nil)
    }

    @Test("BandwidthTestResult read-only mode")
    func bandwidthTestResultReadOnly() {
        let result = BandwidthTestResult(
            hasWriteAccess: false,
            uploadSpeed: nil,
            downloadSpeed: 75_000_000,
            testFileSize: 5 * 1024 * 1024,
            warning: "Server is read-only"
        )

        #expect(result.hasWriteAccess == false)
        #expect(result.uploadSpeed == nil)
        #expect(result.downloadSpeed == 75_000_000)
        #expect(result.warning == "Server is read-only")
    }

    @Test("BandwidthTestResult formatted speeds")
    func bandwidthTestResultFormattedSpeeds() {
        let result = BandwidthTestResult(
            hasWriteAccess: true,
            uploadSpeed: 50_000_000,
            downloadSpeed: 100_000_000,
            testFileSize: 5 * 1024 * 1024,
            warning: nil
        )

        // Formatted strings should contain speed values (optional returns)
        #expect(result.formattedDownloadSpeed != nil)
        #expect(result.formattedUploadSpeed != nil)
        #expect(result.formattedDownloadSpeed?.contains("/s") == true)
        #expect(result.formattedUploadSpeed?.contains("/s") == true)
    }

    @Test("formattedUploadSpeed nil when no upload")
    func formattedUploadSpeedNil() {
        let result = BandwidthTestResult(
            hasWriteAccess: false,
            uploadSpeed: nil,
            downloadSpeed: 50_000_000,
            testFileSize: 5_000_000,
            warning: nil
        )

        #expect(result.formattedUploadSpeed == nil)
    }

    @Test("formattedDownloadSpeed nil when no download")
    func formattedDownloadSpeedNil() {
        let result = BandwidthTestResult(
            hasWriteAccess: false,
            uploadSpeed: nil,
            downloadSpeed: nil,
            testFileSize: 0,
            warning: "No files available"
        )

        #expect(result.formattedDownloadSpeed == nil)
    }

    @Test("Warning message preserved")
    func warningPreserved() {
        let result = BandwidthTestResult(
            hasWriteAccess: false,
            uploadSpeed: nil,
            downloadSpeed: nil,
            testFileSize: 0,
            warning: "Server appears empty, could not test download speed"
        )

        #expect(result.warning == "Server appears empty, could not test download speed")
    }
}

// MARK: - MediaSourceError Tests

@Suite("MediaSourceError Tests")
struct MediaSourceErrorTests {

    @Test("MediaSourceError cases exist")
    func errorCasesExist() {
        let authError = MediaSourceError.authenticationFailed
        let pathError = MediaSourceError.pathNotFound("/test/path")
        let connectionError = MediaSourceError.connectionFailed("timeout")
        let unknownError = MediaSourceError.unknown("something went wrong")

        #expect(authError.errorDescription != nil)
        #expect(pathError.errorDescription != nil)
        #expect(connectionError.errorDescription != nil)
        #expect(unknownError.errorDescription != nil)
    }

    @Test("MediaSourceError path not found includes path")
    func pathNotFoundIncludesPath() {
        let error = MediaSourceError.pathNotFound("/videos/movie.mp4")
        let description = error.errorDescription ?? ""

        #expect(description.contains("video") || description.contains("movie") ||
                description.contains("path") || description.contains("not found") ||
                description.contains("Path"))
    }

    @Test("MediaSourceError connection failed includes message")
    func connectionFailedIncludesMessage() {
        let error = MediaSourceError.connectionFailed("HTTP 500")
        let description = error.errorDescription ?? ""

        #expect(description.contains("500") || description.contains("connection") ||
                description.contains("failed") || description.contains("HTTP") ||
                description.contains("Connection"))
    }

    @Test("isRetryable for timeout")
    func timeoutIsRetryable() {
        let error = MediaSourceError.timeout
        #expect(error.isRetryable == true)
    }

    @Test("isRetryable for noConnection")
    func noConnectionIsRetryable() {
        let error = MediaSourceError.noConnection
        #expect(error.isRetryable == true)
    }

    @Test("isRetryable for connectionFailed")
    func connectionFailedIsRetryable() {
        let error = MediaSourceError.connectionFailed("network error")
        #expect(error.isRetryable == true)
    }

    @Test("isRetryable for authenticationFailed")
    func authenticationFailedNotRetryable() {
        let error = MediaSourceError.authenticationFailed
        #expect(error.isRetryable == false)
    }

    @Test("isRetryable for pathNotFound")
    func pathNotFoundNotRetryable() {
        let error = MediaSourceError.pathNotFound("/invalid")
        #expect(error.isRetryable == false)
    }

    @Test("isRetryable for accessDenied")
    func accessDeniedNotRetryable() {
        let error = MediaSourceError.accessDenied
        #expect(error.isRetryable == false)
    }

    @Test("Error equality same cases")
    func equalitySameCases() {
        #expect(MediaSourceError.authenticationFailed == MediaSourceError.authenticationFailed)
        #expect(MediaSourceError.timeout == MediaSourceError.timeout)
        #expect(MediaSourceError.noConnection == MediaSourceError.noConnection)
        #expect(MediaSourceError.accessDenied == MediaSourceError.accessDenied)
    }

    @Test("Error equality with associated values")
    func equalityAssociatedValues() {
        #expect(MediaSourceError.pathNotFound("/a") == MediaSourceError.pathNotFound("/a"))
        #expect(MediaSourceError.pathNotFound("/a") != MediaSourceError.pathNotFound("/b"))
        #expect(MediaSourceError.connectionFailed("x") == MediaSourceError.connectionFailed("x"))
        #expect(MediaSourceError.connectionFailed("x") != MediaSourceError.connectionFailed("y"))
    }

    @Test("All error cases have descriptions")
    func allCasesHaveDescriptions() {
        let errors: [MediaSourceError] = [
            .connectionFailed("test"),
            .authenticationFailed,
            .pathNotFound("/test"),
            .parsingFailed("xml error"),
            .notADirectory,
            .invalidResponse,
            .bookmarkResolutionFailed,
            .accessDenied,
            .timeout,
            .noConnection,
            .unknown("mystery")
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

// MARK: - MediaSource Configuration Tests

@Suite("MediaSource Configuration Tests")
struct MediaSourceConfigurationTests {

    @Test("WebDAV factory method")
    func webdavFactory() {
        let source = MediaSource.webdav(
            name: "My NAS",
            url: URL(string: "https://nas.local:5006/webdav")!,
            username: "admin"
        )

        #expect(source.type == .webdav)
        #expect(source.name == "My NAS")
        #expect(source.username == "admin")
        #expect(source.url.absoluteString == "https://nas.local:5006/webdav")
        #expect(source.isEnabled == true)
        #expect(source.requiresAuthentication == true)
    }

    @Test("WebDAV without username")
    func webdavWithoutUsername() {
        let source = MediaSource.webdav(
            name: "Public NAS",
            url: URL(string: "https://public.nas/webdav")!
        )

        #expect(source.username == nil)
        #expect(source.requiresAuthentication == false)
    }

    @Test("LocalFolder factory method")
    func localFolderFactory() {
        let url = URL(fileURLWithPath: "/Users/test/Videos")
        let source = MediaSource.localFolder(
            name: "Videos",
            url: url,
            bookmarkData: Data([0x01, 0x02, 0x03])
        )

        #expect(source.type == .localFolder)
        #expect(source.name == "Videos")
        #expect(source.bookmarkData != nil)
        #expect(source.requiresAuthentication == false)
    }

    @Test("MediaSourceType displayName")
    func mediaSourceTypeDisplayName() {
        #expect(!MediaSourceType.webdav.displayName.isEmpty)
        #expect(!MediaSourceType.localFolder.displayName.isEmpty)
    }

    @Test("MediaSourceType systemImage")
    func mediaSourceTypeSystemImage() {
        #expect(!MediaSourceType.webdav.systemImage.isEmpty)
        #expect(!MediaSourceType.localFolder.systemImage.isEmpty)
    }

    @Test("MediaSourceType CaseIterable")
    func mediaSourceTypeCaseIterable() {
        let allCases = MediaSourceType.allCases
        #expect(allCases.contains(.webdav))
        #expect(allCases.contains(.localFolder))
        #expect(allCases.contains(.smb))
        #expect(allCases.count == 3)
    }

    @Test("MediaSource urlDisplayString WebDAV")
    func urlDisplayStringWebDAV() {
        let source = MediaSource.webdav(
            name: "NAS",
            url: URL(string: "https://nas.synology.me/webdav")!
        )

        #expect(source.urlDisplayString == "nas.synology.me")
    }

    @Test("MediaSource urlDisplayString LocalFolder")
    func urlDisplayStringLocalFolder() {
        let source = MediaSource.localFolder(
            name: "Movies",
            url: URL(fileURLWithPath: "/Users/test/Movies")
        )

        #expect(source.urlDisplayString == "Movies")
    }

    @Test("MediaSource is Identifiable")
    func mediaSourceIdentifiable() {
        let source1 = MediaSource.webdav(name: "A", url: URL(string: "https://a.com")!)
        let source2 = MediaSource.webdav(name: "A", url: URL(string: "https://a.com")!)

        // Each source gets unique UUID
        #expect(source1.id != source2.id)
    }

    @Test("MediaSource is Codable")
    func mediaSourceCodable() throws {
        let source = MediaSource.webdav(
            name: "Test NAS",
            url: URL(string: "https://nas.local")!,
            username: "user"
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(MediaSource.self, from: encoded)

        #expect(decoded.name == source.name)
        #expect(decoded.type == source.type)
        #expect(decoded.url == source.url)
        #expect(decoded.username == source.username)
    }
}

// MARK: - MediaFile Tests

@Suite("MediaFile Tests")
struct MediaFileTests {

    private func createTestSource() -> MediaSource {
        MediaSource.webdav(name: "Test", url: URL(string: "https://nas.local")!)
    }

    @Test("MediaFile initialization")
    func mediaFileInit() {
        let source = createTestSource()
        let file = MediaFile(
            source: source,
            path: "/videos/movie.mp4",
            name: "movie.mp4",
            isDirectory: false,
            size: 104857600, // 100 MB
            modifiedDate: Date()
        )

        #expect(file.name == "movie.mp4")
        #expect(file.path == "/videos/movie.mp4")
        #expect(file.isDirectory == false)
        #expect(file.size == 104857600)
    }

    @Test("MediaFile directory type")
    func mediaFileDirectory() {
        let source = MediaSource.localFolder(
            name: "Videos",
            url: URL(fileURLWithPath: "/Users/test/Videos")
        )
        let folder = MediaFile(
            source: source,
            path: "/Movies",
            name: "Movies",
            isDirectory: true,
            size: nil,
            modifiedDate: nil
        )

        #expect(folder.isDirectory == true)
        #expect(folder.size == nil)
    }

    @Test("MediaFile is Identifiable")
    func mediaFileIdentifiable() {
        let source = createTestSource()
        let file = MediaFile(
            source: source,
            path: "/video.mp4",
            name: "video.mp4",
            isDirectory: false,
            size: 1000,
            modifiedDate: nil
        )

        #expect(!file.id.isEmpty)
        #expect(file.id.contains(source.id.uuidString))
    }

    @Test("MediaFile Hashable")
    func mediaFileHashable() {
        let source = createTestSource()
        let file1 = MediaFile(
            source: source,
            path: "/video.mp4",
            name: "video.mp4",
            isDirectory: false,
            size: 1000,
            modifiedDate: nil
        )
        let file2 = MediaFile(
            source: source,
            path: "/video.mp4",
            name: "video.mp4",
            isDirectory: false,
            size: 1000,
            modifiedDate: nil
        )

        // Same path and source should be equal
        #expect(file1 == file2)

        var set = Set<MediaFile>()
        set.insert(file1)
        #expect(set.contains(file2))
    }

    @Test("MediaFile isVideo for video files")
    func isVideoForVideoFiles() {
        let source = createTestSource()
        let extensions = ["mp4", "mkv", "avi", "mov", "webm", "flv", "m4v"]

        for ext in extensions {
            let file = MediaFile(
                source: source,
                path: "/movie.\(ext)",
                name: "movie.\(ext)",
                isDirectory: false
            )
            #expect(file.isVideo == true, "Expected .\(ext) to be video")
        }
    }

    @Test("MediaFile isVideo false for directories")
    func isVideoFalseForDirectories() {
        let source = createTestSource()
        let folder = MediaFile(
            source: source,
            path: "/Videos",
            name: "Videos",
            isDirectory: true
        )

        #expect(folder.isVideo == false)
    }

    @Test("MediaFile isAudio for audio files")
    func isAudioForAudioFiles() {
        let source = createTestSource()
        let extensions = ["mp3", "m4a", "flac", "wav", "ogg", "opus", "aac"]

        for ext in extensions {
            let file = MediaFile(
                source: source,
                path: "/song.\(ext)",
                name: "song.\(ext)",
                isDirectory: false
            )
            #expect(file.isAudio == true, "Expected .\(ext) to be audio")
        }
    }

    @Test("MediaFile isPlayable")
    func isPlayable() {
        let source = createTestSource()

        let videoFile = MediaFile(source: source, path: "/movie.mp4", name: "movie.mp4", isDirectory: false)
        let audioFile = MediaFile(source: source, path: "/song.mp3", name: "song.mp3", isDirectory: false)
        let textFile = MediaFile(source: source, path: "/readme.txt", name: "readme.txt", isDirectory: false)
        let folder = MediaFile(source: source, path: "/Movies", name: "Movies", isDirectory: true)

        #expect(videoFile.isPlayable == true)
        #expect(audioFile.isPlayable == true)
        #expect(textFile.isPlayable == false)
        #expect(folder.isPlayable == false)
    }

    @Test("MediaFile fileExtension")
    func fileExtension() {
        let source = createTestSource()

        let file1 = MediaFile(source: source, path: "/video.MP4", name: "video.MP4", isDirectory: false)
        let file2 = MediaFile(source: source, path: "/movie.MKV", name: "movie.MKV", isDirectory: false)

        // Extensions should be lowercase
        #expect(file1.fileExtension == "mp4")
        #expect(file2.fileExtension == "mkv")
    }

    @Test("MediaFile formattedSize")
    func formattedSize() {
        let source = createTestSource()

        let smallFile = MediaFile(source: source, path: "/small.txt", name: "small.txt", isDirectory: false, size: 1024)
        let largeFile = MediaFile(source: source, path: "/large.mp4", name: "large.mp4", isDirectory: false, size: 1_500_000_000)
        let noSize = MediaFile(source: source, path: "/unknown.dat", name: "unknown.dat", isDirectory: false, size: nil)

        #expect(smallFile.formattedSize != nil)
        #expect(largeFile.formattedSize != nil)
        #expect(noSize.formattedSize == nil)
    }

    @Test("MediaFile systemImage")
    func systemImage() {
        let source = createTestSource()

        let folder = MediaFile(source: source, path: "/Dir", name: "Dir", isDirectory: true)
        let video = MediaFile(source: source, path: "/movie.mp4", name: "movie.mp4", isDirectory: false)
        let audio = MediaFile(source: source, path: "/song.mp3", name: "song.mp3", isDirectory: false)
        let other = MediaFile(source: source, path: "/doc.pdf", name: "doc.pdf", isDirectory: false)

        #expect(folder.systemImage == "folder.fill")
        #expect(video.systemImage == "film")
        #expect(audio.systemImage == "music.note")
        #expect(other.systemImage == "doc")
    }

    @Test("MediaFile url construction")
    func urlConstruction() {
        let source = MediaSource.webdav(name: "NAS", url: URL(string: "https://nas.local/webdav")!)
        let file = MediaFile(source: source, path: "/videos/movie.mp4", name: "movie.mp4", isDirectory: false)

        #expect(file.url.absoluteString.contains("nas.local"))
        #expect(file.url.absoluteString.contains("movie.mp4"))
    }

    @Test("MediaFile toVideo conversion")
    func toVideoConversion() {
        let source = MediaSource.webdav(name: "NAS", url: URL(string: "https://nas.local")!)
        let modDate = Date()
        let file = MediaFile(
            source: source,
            path: "/movies/My Movie.mp4",
            name: "My Movie.mp4",
            isDirectory: false,
            size: 1_000_000,
            modifiedDate: modDate
        )

        let video = file.toVideo()

        #expect(video.title == "My Movie")
        #expect(video.author.name == "NAS")
        #expect(video.publishedAt == modDate)
        #expect(video.isLive == false)
    }

    @Test("MediaFile toStream conversion")
    func toStreamConversion() {
        let source = MediaSource.webdav(name: "NAS", url: URL(string: "https://nas.local")!)
        let file = MediaFile(
            source: source,
            path: "/movie.mkv",
            name: "movie.mkv",
            isDirectory: false
        )

        let stream = file.toStream(authHeaders: ["Authorization": "Basic abc123"])

        #expect(stream.format == "mkv")
        #expect(stream.httpHeaders?["Authorization"] == "Basic abc123")
    }

    @Test("MediaFile preview samples")
    func previewSamples() {
        let file = MediaFile.preview
        let folder = MediaFile.folderPreview

        #expect(file.isDirectory == false)
        #expect(file.isVideo == true)
        #expect(folder.isDirectory == true)
    }

    @Test("MediaFile video extensions coverage")
    func videoExtensionsCoverage() {
        // Verify all expected video extensions are included
        let expected = ["mp4", "m4v", "mov", "mkv", "avi", "webm", "wmv", "flv", "mpg", "mpeg", "3gp", "ts", "vob"]
        for ext in expected {
            #expect(MediaFile.videoExtensions.contains(ext), "Missing video extension: \(ext)")
        }
    }

    @Test("MediaFile audio extensions coverage")
    func audioExtensionsCoverage() {
        // Verify all expected audio extensions are included
        let expected = ["mp3", "m4a", "aac", "flac", "wav", "ogg", "opus", "wma", "aiff"]
        for ext in expected {
            #expect(MediaFile.audioExtensions.contains(ext), "Missing audio extension: \(ext)")
        }
    }
}
