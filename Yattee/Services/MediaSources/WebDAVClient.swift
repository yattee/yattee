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
