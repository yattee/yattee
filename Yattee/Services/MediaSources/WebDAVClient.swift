//
//  WebDAVClient.swift
//  Yattee
//
//  WebDAV client for listing and accessing remote files.
//

import Foundation

/// Actor-based WebDAV client for media source operations.
actor WebDAVClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public Methods

    /// Lists files in a directory on a WebDAV server.
    /// - Parameters:
    ///   - path: The path to list (relative to source URL).
    ///   - source: The media source configuration.
    ///   - password: The password for authentication (stored separately in Keychain).
    /// - Returns: Array of files and folders in the directory.
    func listFiles(
        at path: String,
        source: MediaSource,
        password: String?
    ) async throws -> [MediaFile] {
        guard source.type == .webdav else {
            throw MediaSourceError.unknown("Invalid source type for WebDAV client")
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let requestURL = source.url.appendingPathComponent(normalizedPath)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        // Add authentication header
        if let authHeader = buildAuthHeader(username: source.username, password: password) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        // PROPFIND request body
        request.httpBody = propfindRequestBody.data(using: .utf8)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw MediaSourceError.connectionFailed(error.localizedDescription)
        }

        // Validate response
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299, 207: // 207 Multi-Status is standard WebDAV success
                break
            case 401:
                // Log auth failure details for debugging
                let wwwAuth = httpResponse.allHeaderFields["WWW-Authenticate"] as? String ?? "none"
                LoggingService.shared.logMediaSourcesError("WebDAV auth failed", error: nil)
                LoggingService.shared.logMediaSourcesDebug("WebDAV auth details: URL=\(requestURL.absoluteString), WWW-Authenticate=\(wwwAuth), username=\(source.username ?? "nil"), hasPassword=\(password != nil && !password!.isEmpty)")
                throw MediaSourceError.authenticationFailed
            case 404:
                throw MediaSourceError.pathNotFound(path)
            default:
                throw MediaSourceError.connectionFailed("HTTP \(httpResponse.statusCode)")
            }
        }

        // Parse XML response
        return try parseMultiStatusResponse(data, source: source, basePath: normalizedPath)
    }

    /// Tests the connection to a WebDAV server.
    /// - Parameters:
    ///   - source: The media source configuration.
    ///   - password: The password for authentication.
    /// - Returns: True if connection is successful.
    func testConnection(
        source: MediaSource,
        password: String?
    ) async throws -> Bool {
        _ = try await listFiles(at: "/", source: source, password: password)
        return true
    }

    // MARK: - Bandwidth Testing

    /// Tests bandwidth to a WebDAV server with auto-detection of write access.
    /// - Parameters:
    ///   - source: The media source configuration.
    ///   - password: The password for authentication.
    ///   - testFileSizeMB: Size of test file in megabytes (default 5 MB).
    ///   - progressHandler: Optional callback for progress updates (status string).
    /// - Returns: BandwidthTestResult with speed measurements.
    func testBandwidth(
        source: MediaSource,
        password: String?,
        testFileSizeMB: Int = 20,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> BandwidthTestResult {
        let bandwidthTestSize = Int64(testFileSizeMB) * 1024 * 1024
        guard source.type == .webdav else {
            throw MediaSourceError.unknown("Invalid source type for WebDAV client")
        }

        // First, verify basic connectivity
        progressHandler?("Connecting...")
        _ = try await listFiles(at: "/", source: source, password: password)

        // Try write test first
        do {
            return try await performWriteTest(source: source, password: password, testSize: bandwidthTestSize, progressHandler: progressHandler)
        } catch let error as MediaSourceError {
            // Check if it's a permission error - fall back to read-only
            if case .connectionFailed(let message) = error,
               message.contains("403") || message.contains("405") || message.contains("401") {
                return try await performReadOnlyTest(source: source, password: password, testSize: bandwidthTestSize, progressHandler: progressHandler)
            }
            throw error
        } catch {
            // For other errors, try read-only test
            return try await performReadOnlyTest(source: source, password: password, testSize: bandwidthTestSize, progressHandler: progressHandler)
        }
    }

    /// Performs a write test: upload, download, and delete a test file.
    private func performWriteTest(
        source: MediaSource,
        password: String?,
        testSize: Int64,
        progressHandler: (@Sendable (String) -> Void)?
    ) async throws -> BandwidthTestResult {
        let testFileName = ".yattee-bandwidth-test-\(UUID().uuidString).tmp"

        // Find a writable location - try first subfolder (root may not be writable, e.g. Synology shares listing)
        let writablePath = try await findWritablePath(source: source, password: password)
        let testPath = writablePath + testFileName

        // Generate test data (zeros are fine for bandwidth testing)
        let testData = Data(count: Int(testSize))

        // Upload test
        progressHandler?("Uploading...")
        let uploadStart = CFAbsoluteTimeGetCurrent()
        try await uploadFile(data: testData, to: testPath, source: source, password: password)
        let uploadDuration = CFAbsoluteTimeGetCurrent() - uploadStart
        let uploadSpeed = Double(testSize) / uploadDuration

        progressHandler?("Downloading...")

        // Download test
        let downloadStart = CFAbsoluteTimeGetCurrent()
        _ = try await downloadFile(from: testPath, source: source, password: password)
        let downloadDuration = CFAbsoluteTimeGetCurrent() - downloadStart
        let downloadSpeed = Double(testSize) / downloadDuration

        progressHandler?("Cleaning up...")

        // Delete test file (ignore errors - cleanup is best effort)
        try? await deleteFile(at: testPath, source: source, password: password)

        progressHandler?("Complete")

        return BandwidthTestResult(
            hasWriteAccess: true,
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed,
            testFileSize: testSize,
            warning: nil
        )
    }

    /// Performs a read-only test by finding and downloading an existing file.
    private func performReadOnlyTest(
        source: MediaSource,
        password: String?,
        testSize: Int64,
        progressHandler: (@Sendable (String) -> Void)?
    ) async throws -> BandwidthTestResult {
        progressHandler?("Finding test file...")

        // Find a file to download
        guard let testFile = try await findTestFile(source: source, password: password) else {
            // Server is empty or has no accessible files
            progressHandler?("Complete")
            return BandwidthTestResult(
                hasWriteAccess: false,
                uploadSpeed: nil,
                downloadSpeed: nil,
                testFileSize: 0,
                warning: "No files available for speed test"
            )
        }

        progressHandler?("Downloading...")

        // Download the file (or first N MB of it based on test size)
        let downloadStart = CFAbsoluteTimeGetCurrent()
        let downloadedSize = try await downloadFilePartial(
            from: testFile.path,
            source: source,
            password: password,
            maxBytes: testSize
        )
        let downloadDuration = CFAbsoluteTimeGetCurrent() - downloadStart
        let downloadSpeed = Double(downloadedSize) / downloadDuration

        progressHandler?("Complete")

        return BandwidthTestResult(
            hasWriteAccess: false,
            uploadSpeed: nil,
            downloadSpeed: downloadSpeed,
            testFileSize: Int64(downloadedSize),
            warning: nil
        )
    }

    /// Finds a writable path for the bandwidth test file.
    /// Tries root first, then first available subfolder (useful for Synology where root is shares listing).
    private func findWritablePath(
        source: MediaSource,
        password: String?
    ) async throws -> String {
        // List root to find first subfolder
        let rootFiles = try await listFiles(at: "/", source: source, password: password)

        // Try first directory as writable location
        if let firstDir = rootFiles.first(where: { $0.isDirectory }) {
            return firstDir.path.hasSuffix("/") ? firstDir.path : firstDir.path + "/"
        }

        // Fall back to root if no subdirectories
        return "/"
    }

    /// Finds a suitable file for download testing.
    private func findTestFile(
        source: MediaSource,
        password: String?
    ) async throws -> MediaFile? {
        return try await findFileRecursive(
            in: "/",
            source: source,
            password: password,
            depth: 0,
            maxDepth: 2
        )
    }

    /// Recursively searches for a suitable test file.
    private func findFileRecursive(
        in path: String,
        source: MediaSource,
        password: String?,
        depth: Int,
        maxDepth: Int
    ) async throws -> MediaFile? {
        let files = try await listFiles(at: path, source: source, password: password)

        // First, look for any file with reasonable size (> 100KB)
        if let file = files.first(where: { !$0.isDirectory && ($0.size ?? 0) > 100_000 }) {
            return file
        }

        // If at max depth, just return any file
        if depth >= maxDepth {
            return files.first(where: { !$0.isDirectory })
        }

        // Otherwise, recurse into directories
        for dir in files.filter({ $0.isDirectory }) {
            if let file = try? await findFileRecursive(
                in: dir.path,
                source: source,
                password: password,
                depth: depth + 1,
                maxDepth: maxDepth
            ) {
                return file
            }
        }

        return nil
    }

    // MARK: - WebDAV Operations for Bandwidth Test

    /// Uploads data to a WebDAV server.
    private func uploadFile(
        data: Data,
        to path: String,
        source: MediaSource,
        password: String?
    ) async throws {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let requestURL = source.url.appendingPathComponent(normalizedPath)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 120 // 2 minutes for upload

        if let authHeader = buildAuthHeader(username: source.username, password: password) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 201 else {
                throw MediaSourceError.connectionFailed("Upload failed: HTTP \(httpResponse.statusCode)")
            }
        }
    }

    /// Downloads a file from a WebDAV server.
    private func downloadFile(
        from path: String,
        source: MediaSource,
        password: String?
    ) async throws -> Data {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let requestURL = source.url.appendingPathComponent(normalizedPath)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 120

        if let authHeader = buildAuthHeader(username: source.username, password: password) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw MediaSourceError.connectionFailed("Download failed: HTTP \(httpResponse.statusCode)")
            }
        }

        return data
    }

    /// Downloads up to maxBytes of a file (using Range header if supported).
    private func downloadFilePartial(
        from path: String,
        source: MediaSource,
        password: String?,
        maxBytes: Int64
    ) async throws -> Int {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let requestURL = source.url.appendingPathComponent(normalizedPath)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("bytes=0-\(maxBytes - 1)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 120

        if let authHeader = buildAuthHeader(username: source.username, password: password) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            // Accept 200 (full file) or 206 (partial content)
            guard httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
                throw MediaSourceError.connectionFailed("Download failed: HTTP \(httpResponse.statusCode)")
            }
        }

        return data.count
    }

    /// Deletes a file from a WebDAV server.
    private func deleteFile(
        at path: String,
        source: MediaSource,
        password: String?
    ) async throws {
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let requestURL = source.url.appendingPathComponent(normalizedPath)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        if let authHeader = buildAuthHeader(username: source.username, password: password) {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            // Accept 200, 204 (No Content), or 404 (already gone)
            guard (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404 else {
                throw MediaSourceError.connectionFailed("Delete failed: HTTP \(httpResponse.statusCode)")
            }
        }
    }

    /// Builds authentication headers for a WebDAV request.
    /// - Parameters:
    ///   - source: The media source.
    ///   - password: The password from Keychain.
    /// - Returns: Dictionary of HTTP headers for authentication.
    func authHeaders(
        for source: MediaSource,
        password: String?
    ) -> [String: String]? {
        guard let authHeader = buildAuthHeader(username: source.username, password: password) else {
            return nil
        }
        return ["Authorization": authHeader]
    }

    // MARK: - Private Methods

    private func buildAuthHeader(username: String?, password: String?) -> String? {
        guard let username, !username.isEmpty else { return nil }
        let credentials = "\(username):\(password ?? "")"
        guard let data = credentials.data(using: .utf8) else { return nil }
        return "Basic \(data.base64EncodedString())"
    }

    private func mapURLError(_ error: URLError) -> MediaSourceError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .userAuthenticationRequired:
            return .authenticationFailed
        default:
            return .connectionFailed(error.localizedDescription)
        }
    }

    // MARK: - XML Parsing

    /// PROPFIND request body asking for file properties.
    private let propfindRequestBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
        <D:prop>
            <D:displayname/>
            <D:getcontentlength/>
            <D:getlastmodified/>
            <D:getcontenttype/>
            <D:resourcetype/>
        </D:prop>
    </D:propfind>
    """

    private func parseMultiStatusResponse(
        _ data: Data,
        source: MediaSource,
        basePath: String
    ) throws -> [MediaFile] {
        let parser = WebDAVResponseParser(source: source, basePath: basePath)
        return try parser.parse(data)
    }
}

// MARK: - Bandwidth Test Result

/// Result of a bandwidth test on a WebDAV server.
struct BandwidthTestResult: Sendable {
    /// Whether the server allows write access (upload/delete).
    let hasWriteAccess: Bool

    /// Upload speed in bytes per second (nil if write access unavailable).
    let uploadSpeed: Double?

    /// Download speed in bytes per second.
    let downloadSpeed: Double?

    /// Size of the test file used (in bytes).
    let testFileSize: Int64

    /// Any warning message (e.g., "Server appears empty, could not test download speed").
    let warning: String?

    /// Formatted upload speed string (e.g., "12.5 MB/s").
    var formattedUploadSpeed: String? {
        guard let speed = uploadSpeed else { return nil }
        return Self.formatSpeed(speed)
    }

    /// Formatted download speed string (e.g., "45.2 MB/s").
    var formattedDownloadSpeed: String? {
        guard let speed = downloadSpeed else { return nil }
        return Self.formatSpeed(speed)
    }

    private static func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }
}

// MARK: - WebDAV Response Parser

/// Parses WebDAV PROPFIND multi-status XML responses.
private final class WebDAVResponseParser: NSObject, XMLParserDelegate {
    private let source: MediaSource
    private let basePath: String

    private var files: [MediaFile] = []
    private var currentResponse: ResponseData?
    private var currentElement: String = ""
    private var currentText: String = ""

    // Temporary storage for current response properties
    private struct ResponseData {
        var href: String = ""
        var displayName: String?
        var contentLength: Int64?
        var lastModified: Date?
        var contentType: String?
        var isCollection: Bool = false
    }

    init(source: MediaSource, basePath: String) {
        self.source = source
        self.basePath = basePath
    }

    func parse(_ data: Data) throws -> [MediaFile] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            if let error = parser.parserError {
                throw MediaSourceError.parsingFailed(error.localizedDescription)
            }
            throw MediaSourceError.parsingFailed("Unknown XML parsing error")
        }

        return files
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "response" {
            currentResponse = ResponseData()
        } else if elementName == "collection" {
            currentResponse?.isCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "href":
            currentResponse?.href = text
        case "displayname":
            if !text.isEmpty {
                currentResponse?.displayName = text
            }
        case "getcontentlength":
            currentResponse?.contentLength = Int64(text)
        case "getlastmodified":
            currentResponse?.lastModified = parseHTTPDate(text)
        case "getcontenttype":
            if !text.isEmpty {
                currentResponse?.contentType = text
            }
        case "response":
            if let response = currentResponse {
                if let file = createMediaFile(from: response) {
                    files.append(file)
                }
            }
            currentResponse = nil
        default:
            break
        }

        currentText = ""
    }

    private func createMediaFile(from response: ResponseData) -> MediaFile? {
        // Decode URL-encoded path
        let href = response.href.removingPercentEncoding ?? response.href

        // Extract path relative to source URL
        var path = href
        if let sourceHost = source.url.host {
            // Remove host prefix if present
            if path.contains(sourceHost) {
                if let range = path.range(of: sourceHost) {
                    let afterHost = path[range.upperBound...]
                    path = String(afterHost)
                }
            }
        }

        // Remove leading/trailing slashes for consistency
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Skip the root directory itself
        let normalizedBasePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == normalizedBasePath || path.isEmpty {
            return nil
        }

        // Get display name
        let name: String
        if let displayName = response.displayName, !displayName.isEmpty {
            name = displayName
        } else {
            // Fall back to last path component
            name = (path as NSString).lastPathComponent
        }

        // Skip hidden files
        if name.hasPrefix(".") {
            return nil
        }

        return MediaFile(
            source: source,
            path: "/" + path,
            name: name,
            isDirectory: response.isCollection,
            size: response.contentLength,
            modifiedDate: response.lastModified,
            mimeType: response.contentType
        )
    }

    private func parseHTTPDate(_ string: String) -> Date? {
        // HTTP dates can be in various formats
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEEE, dd-MMM-yy HH:mm:ss zzz"
                return f
            }(),
            {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "EEE MMM d HH:mm:ss yyyy"
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        // Try ISO 8601
        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: string)
    }
}
