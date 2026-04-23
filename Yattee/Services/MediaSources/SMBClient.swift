//
//  SMBClient.swift
//  Yattee
//
//  SMB/CIFS client for listing and accessing remote files.
//

import Foundation

/// Actor-based SMB client for media source operations.
actor SMBClient {
    
    // Cache of SMB bridge contexts per source ID
    // Reusing contexts avoids creating new ones for each operation
    private var contextCache: [UUID: SMBBridgeContext] = [:]
    
    // Track if an operation is in progress per source
    // If true, new requests will fail fast instead of queueing
    private var operationInProgress: Set<UUID> = []
    
    // Callback to check if SMB playback is currently active
    // When SMB video is playing via MPV/FFmpeg, directory browsing must be blocked
    // because libsmbclient has internal state conflicts when used concurrently
    private var isSMBPlaybackActiveCallback: (@Sendable @MainActor () -> Bool)?

    init() {}
    
    /// Sets the callback to check if SMB playback is active.
    /// This must be called before using directory listing operations.
    func setPlaybackActiveCallback(_ callback: @escaping @Sendable @MainActor () -> Bool) {
        self.isSMBPlaybackActiveCallback = callback
    }

    // MARK: - Public Methods

    /// Constructs a playback URL for an SMB file with embedded credentials.
    /// - Parameters:
    ///   - file: The media file to construct a URL for.
    ///   - source: The media source configuration.
    ///   - password: The password for authentication (stored separately in Keychain).
    /// - Returns: A URL with embedded credentials for MPV playback.
    func constructPlaybackURL(
        for file: MediaFile,
        source: MediaSource,
        password: String?
    ) throws -> URL {
        guard source.type == .smb else {
            throw MediaSourceError.unknown("Invalid source type for SMB client")
        }

        // Extract components from source URL
        guard let host = source.url.host else {
            throw MediaSourceError.unknown("SMB source URL missing host")
        }

        // Extract share from file path (first path component)
        // file.path format: "ShareName/folder/file.mp4"
        let pathComponents = file.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard let share = pathComponents.first else {
            throw MediaSourceError.unknown("File path missing share name")
        }
        
        let filePathWithinShare = pathComponents.count > 1 ? String(pathComponents[1]) : ""

        // Percent-encode credentials for URL embedding
        let encodedUsername = source.username?.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? ""
        let encodedPassword = password?.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? ""

        // Build SMB URL: smb://user:pass@host/share/path/to/file
        var urlString = "smb://"
        
        if !encodedUsername.isEmpty {
            urlString += encodedUsername
            if !encodedPassword.isEmpty {
                urlString += ":" + encodedPassword
            }
            urlString += "@"
        }
        
        urlString += host
        urlString += "/" + share
        
        // Add file path within the share
        if !filePathWithinShare.isEmpty {
            urlString += "/" + filePathWithinShare
        }

        guard let url = URL(string: urlString) else {
            throw MediaSourceError.unknown("Failed to construct SMB URL")
        }

        LoggingService.shared.logMediaSourcesDebug("Constructed SMB URL: \(url.sanitized)")
        return url
    }
    
    /// Downloads a subtitle file from SMB to a temporary location.
    /// - Parameters:
    ///   - file: The subtitle MediaFile to download.
    ///   - source: The media source configuration.
    ///   - password: The password for authentication.
    ///   - videoID: The video ID for organizing temp files.
    /// - Returns: A local file:// URL to the downloaded subtitle.
    func downloadSubtitleToTemp(
        file: MediaFile,
        source: MediaSource,
        password: String?,
        videoID: String
    ) async throws -> URL {
        guard source.type == .smb else {
            throw MediaSourceError.unknown("Invalid source type for SMB client")
        }
        
        guard file.isSubtitle else {
            throw MediaSourceError.unknown("File is not a subtitle")
        }
        
        LoggingService.shared.logMediaSources("Downloading subtitle: \(file.name)")
        
        // Get or create cached bridge context for this source
        let bridge: SMBBridgeContext
        if let cached = contextCache[source.id] {
            LoggingService.shared.logMediaSourcesDebug("Using cached SMB context for subtitle download: \(source.id)")
            bridge = cached
        } else {
            LoggingService.shared.logMediaSourcesDebug("Creating new SMB context for subtitle download: \(source.id)")
            let workgroup = source.smbWorkgroup ?? "WORKGROUP"
            let protocolVersion = source.smbProtocolVersion ?? .auto
            
            bridge = SMBBridgeContext(
                workgroup: workgroup,
                username: source.username,
                password: password,
                protocolVersion: protocolVersion
            )
            
            // Initialize the bridge
            try await bridge.initialize()
            
            // Cache it for future use
            contextCache[source.id] = bridge
        }
        
        // Construct SMB URL (without credentials - used internally by C bridge)
        guard let host = source.url.host else {
            throw MediaSourceError.unknown("SMB source URL missing host")
        }
        
        let pathComponents = file.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard let share = pathComponents.first else {
            throw MediaSourceError.unknown("File path missing share name")
        }
        let filePathWithinShare = pathComponents.count > 1 ? String(pathComponents[1]) : ""
        
        let smbURL = "smb://\(host)/\(share)" + (filePathWithinShare.isEmpty ? "" : "/\(filePathWithinShare)")
        
        // Create temp directory for this video's subtitles
        // Use hash of videoID to keep path short (filesystem limits)
        let videoHash = String(videoID.hashValue)
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yattee-subtitles", isDirectory: true)
            .appendingPathComponent(videoHash, isDirectory: true)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Generate local filename: hash_baseName.extension
        let localFileName = "\(videoHash)_\(file.baseName).\(file.fileExtension)"
        let localURL = tempDir.appendingPathComponent(localFileName)
        
        LoggingService.shared.logMediaSourcesDebug("Downloading from: \(smbURL)")
        LoggingService.shared.logMediaSourcesDebug("Downloading to: \(localURL.path)")

        // Download the file using the bridge
        try await bridge.downloadFile(from: smbURL, to: localURL.path)

        LoggingService.shared.logMediaSources("Downloaded subtitle to: \(localURL.path)")
        return localURL
    }

    /// Tests the connection to an SMB server by attempting to list shares.
    /// - Parameters:
    ///   - source: The media source configuration.
    ///   - password: The password for authentication.
    /// - Returns: True if connection succeeds.
    func testConnection(
        source: MediaSource,
        password: String?
    ) async throws -> Bool {
        guard source.type == .smb else {
            throw MediaSourceError.unknown("Invalid source type for SMB client")
        }

        // Validate URL has required components
        guard let host = source.url.host else {
            throw MediaSourceError.unknown("SMB URL missing host")
        }

        // Validate credentials if username provided
        if source.username != nil && (password == nil || password!.isEmpty) {
            throw MediaSourceError.authenticationFailed
        }

        // Test by attempting to list shares
        let workgroup = source.smbWorkgroup ?? "WORKGROUP"
        let protocolVersion = source.smbProtocolVersion ?? .auto
        
        let bridge = SMBBridgeContext(
            workgroup: workgroup,
            username: source.username,
            password: password,
            protocolVersion: protocolVersion
        )
        
        try await bridge.initialize()
        try await bridge.testConnection(to: "smb://\(host)/")

        LoggingService.shared.logMediaSources("SMB connection test passed for \(source.url.sanitized)")
        return true
    }

    /// Lists files in a directory on an SMB server.
    /// 
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
        guard source.type == .smb else {
            throw MediaSourceError.unknown("Invalid source type for SMB client")
        }
        
        // Check if SMB playback is active - if so, we cannot use libsmbclient
        // because it has internal state conflicts with MPV/FFmpeg's concurrent usage
        if let callback = isSMBPlaybackActiveCallback {
            let isActive = await callback()
            if isActive {
                LoggingService.shared.logMediaSourcesWarning("SMB playback is active, cannot browse directories concurrently")
                throw MediaSourceError.unknown("Cannot browse SMB while playing video from SMB. Please stop playback first or collapse the browser.")
            }
        }
        
        // If an operation is already in progress for this source, fail fast
        // This prevents queueing up requests that will timeout
        if operationInProgress.contains(source.id) {
            LoggingService.shared.logMediaSourcesWarning("SMB operation already in progress for source \(source.id), skipping request")
            throw MediaSourceError.unknown("Operation already in progress")
        }

        // Extract components from source URL
        guard let host = source.url.host else {
            throw MediaSourceError.unknown("SMB source URL missing host")
        }

        // Clean up the path
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        // Detect if we're at root level (listing shares) or inside a share (listing files/dirs)
        let isListingShares = cleanPath.isEmpty || cleanPath == "/"
        
        // Build SMB URL based on level
        let urlString: String
        if isListingShares {
            // List shares at root: smb://server/
            urlString = "smb://\(host)/"
            LoggingService.shared.logMediaSourcesDebug("Listing shares on SMB server: \(urlString)")
        } else {
            // List files/dirs within a share: smb://server/share/path
            urlString = "smb://\(host)/\(cleanPath)"
            LoggingService.shared.logMediaSourcesDebug("Listing SMB directory: \(urlString)")
        }
        
        // Mark operation as in progress
        operationInProgress.insert(source.id)
        defer {
            operationInProgress.remove(source.id)
        }
        
        // Check for cancellation before starting
        try Task.checkCancellation()
        
        // Get or create cached bridge context for this source
        let bridge: SMBBridgeContext
        if let cached = contextCache[source.id] {
            LoggingService.shared.logMediaSourcesDebug("Using cached SMB context for source: \(source.id)")
            bridge = cached
        } else {
            LoggingService.shared.logMediaSourcesDebug("Creating new SMB context for source: \(source.id)")
            let workgroup = source.smbWorkgroup ?? "WORKGROUP"
            let protocolVersion = source.smbProtocolVersion ?? .auto
            
            bridge = SMBBridgeContext(
                workgroup: workgroup,
                username: source.username,
                password: password,
                protocolVersion: protocolVersion
            )
            
            // Initialize the bridge
            try await bridge.initialize()
            
            // Cache it for future use
            contextCache[source.id] = bridge
        }
        
        // Check for cancellation before calling C code
        try Task.checkCancellation()
        
        LoggingService.shared.logMediaSourcesDebug("About to call bridge.listDirectory for: \(urlString)")

        // List directory contents
        let fileEntries = try await bridge.listDirectory(at: urlString)

        LoggingService.shared.logMediaSourcesDebug("bridge.listDirectory returned \(fileEntries.count) entries")
        
        // Check for empty results when listing shares
        if isListingShares && fileEntries.isEmpty {
            throw MediaSourceError.unknown("No accessible shares found on this server. Check credentials and permissions.")
        }
        
        // Convert to MediaFile array
        let mediaFiles = fileEntries.map { entry -> MediaFile in
            let fullPath = cleanPath.isEmpty ? entry.name : "\(cleanPath)/\(entry.name)"
            
            return MediaFile(
                source: source,
                path: fullPath,
                name: entry.name,
                isDirectory: entry.isDirectory || entry.isShare,  // Shares are treated as directories
                isShare: entry.isShare,
                size: entry.size,
                modifiedDate: entry.modifiedDate,
                createdDate: entry.createdDate
            )
        }
        
        LoggingService.shared.logMediaSources("Listed \(mediaFiles.count) \(isListingShares ? "shares" : "files") from SMB: \(urlString)")
        return mediaFiles
    }

    // MARK: - Helper Methods

    /// Validates SMB URL format.
    private func validateSMBURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "smb" else {
            throw MediaSourceError.unknown("URL must use smb:// scheme")
        }

        guard url.host != nil else {
            throw MediaSourceError.unknown("SMB URL missing host")
        }
    }
    
    /// Clears cached SMB context for a specific source.
    /// Call this when source credentials change or connection fails.
    func clearCache(for source: MediaSource) {
        contextCache.removeValue(forKey: source.id)
        LoggingService.shared.logMediaSourcesDebug("Cleared SMB context cache for source: \(source.id)")
    }

    /// Clears all cached SMB contexts.
    func clearAllCaches() {
        contextCache.removeAll()
        LoggingService.shared.logMediaSourcesDebug("Cleared all SMB context caches")
    }
}

// MARK: - File Download

extension SMBClient {
    /// Downloads a file from SMB to the specified downloads directory.
    /// - Parameters:
    ///   - filePath: The file path within the source (e.g., "ShareName/folder/file.mp4").
    ///   - source: The media source configuration.
    ///   - password: The password for authentication.
    ///   - downloadsDirectory: The directory to save the file to.
    ///   - progressHandler: Optional callback for progress updates (bytes downloaded, total bytes if known).
    /// - Returns: The local file URL and file size.
    func downloadFileToDownloads(
        filePath: String,
        source: MediaSource,
        password: String?,
        downloadsDirectory: URL,
        progressHandler: (@Sendable (Int64, Int64?) -> Void)? = nil
    ) async throws -> (localURL: URL, fileSize: Int64) {
        guard source.type == .smb else {
            throw MediaSourceError.unknown("Invalid source type for SMB client")
        }

        LoggingService.shared.logMediaSources("Downloading SMB file: \(filePath)")

        // Get or create cached bridge context for this source
        let bridge: SMBBridgeContext
        if let cached = contextCache[source.id] {
            LoggingService.shared.logMediaSourcesDebug("Using cached SMB context for download: \(source.id)")
            bridge = cached
        } else {
            LoggingService.shared.logMediaSourcesDebug("Creating new SMB context for download: \(source.id)")
            let workgroup = source.smbWorkgroup ?? "WORKGROUP"
            let protocolVersion = source.smbProtocolVersion ?? .auto

            bridge = SMBBridgeContext(
                workgroup: workgroup,
                username: source.username,
                password: password,
                protocolVersion: protocolVersion
            )

            // Initialize the bridge
            try await bridge.initialize()

            // Cache it for future use
            contextCache[source.id] = bridge
        }

        // Construct SMB URL (without credentials - used internally by C bridge)
        guard let host = source.url.host else {
            throw MediaSourceError.unknown("SMB source URL missing host")
        }

        let pathComponents = filePath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard let share = pathComponents.first else {
            throw MediaSourceError.unknown("File path missing share name")
        }
        let filePathWithinShare = pathComponents.count > 1 ? String(pathComponents[1]) : ""

        let smbURL = "smb://\(host)/\(share)" + (filePathWithinShare.isEmpty ? "" : "/\(filePathWithinShare)")

        // Generate local filename from SMB path
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        // Ensure unique filename if file already exists
        var localURL = downloadsDirectory.appendingPathComponent(fileName)
        localURL = uniqueDestinationURL(for: localURL)

        LoggingService.shared.logMediaSourcesDebug("Downloading from: \(smbURL)")
        LoggingService.shared.logMediaSourcesDebug("Downloading to: \(localURL.path)")

        // Download the file using the bridge
        try await bridge.downloadFile(from: smbURL, to: localURL.path)

        // Get file size after download
        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = attrs[.size] as? Int64 ?? 0

        LoggingService.shared.logMediaSources("Downloaded SMB file to: \(localURL.path), size: \(fileSize)")
        return (localURL, fileSize)
    }

    /// Generates a unique file URL by appending numbers if the file already exists.
    private func uniqueDestinationURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        var counter = 1
        var newURL = url

        while fileManager.fileExists(atPath: newURL.path) {
            let newName = fileExtension.isEmpty
                ? "\(baseName) (\(counter))"
                : "\(baseName) (\(counter)).\(fileExtension)"
            newURL = directory.appendingPathComponent(newName)
            counter += 1
        }

        return newURL
    }
}

// MARK: - Bandwidth Testing

extension SMBClient {

    /// Tests bandwidth to an SMB server.
    /// 
    /// Note: This is a placeholder implementation.
    /// Real bandwidth testing would require file upload/download operations.
    /// 
    /// - Parameters:
    ///   - source: The media source configuration.
    ///   - password: The password for authentication.
    ///   - testFileSizeMB: Size of test file in megabytes.
    ///   - progressHandler: Optional callback for progress updates.
    /// - Returns: BandwidthTestResult with speed measurements (same type as WebDAV).
    func testBandwidth(
        source: MediaSource,
        password: String?,
        testFileSizeMB: Int = 5,
        progressHandler: (@Sendable (String) -> Void)? = nil
    ) async throws -> BandwidthTestResult {
        guard source.type == .smb else {
            throw MediaSourceError.unknown("Invalid source type for SMB client")
        }

        progressHandler?("Connecting...")
        
        // Validate connection
        _ = try await testConnection(source: source, password: password)
        
        progressHandler?("Complete")

        // TODO: Implement actual bandwidth testing
        LoggingService.shared.logMediaSourcesWarning("SMB bandwidth testing not yet implemented")
        
        return BandwidthTestResult(
            hasWriteAccess: false,
            uploadSpeed: nil,
            downloadSpeed: nil,
            testFileSize: 0,
            warning: "Bandwidth testing not available for SMB sources"
        )
    }
}

// MARK: - URL Extension for Sanitization

extension URL {
    /// Returns a sanitized URL string with credentials hidden.
    /// Used for secure logging without exposing passwords.
    var sanitized: String {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        if components?.user != nil {
            components?.user = "***"
        }
        if components?.password != nil {
            components?.password = "***"
        }
        return components?.string ?? absoluteString
    }
}
