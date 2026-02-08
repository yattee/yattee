//
//  MediaSource.swift
//  Yattee
//
//  Represents a media source configuration for browsing local or remote files.
//

import Foundation

/// The type of media source.
enum MediaSourceType: String, Codable, Hashable, Sendable, CaseIterable {
    case webdav        // Remote WebDAV server
    case localFolder   // Local folder (iOS Files app / macOS directory)
    case smb           // SMB/CIFS network share

    var displayName: String {
        switch self {
        case .webdav:
            return String(localized: "sources.type.webdav")
        case .localFolder:
            return String(localized: "sources.type.localFolder")
        case .smb:
            return String(localized: "sources.type.smb")
        }
    }

    var systemImage: String {
        switch self {
        case .webdav:
            return "externaldrive.connected.to.line.below"
        case .localFolder:
            return "folder"
        case .smb:
            return "externaldrive.connected.to.line.below"
        }
    }
}

/// Represents a configured media source for browsing files.
struct MediaSource: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let type: MediaSourceType
    let url: URL
    var isEnabled: Bool
    let dateAdded: Date

    // WebDAV-specific
    var username: String?

    // Local folder-specific - security-scoped bookmark data for persistent access
    var bookmarkData: Data?

    // Whether to allow invalid/self-signed SSL certificates (WebDAV only)
    var allowInvalidCertificates: Bool
    
    // SMB-specific
    var smbWorkgroup: String?
    var smbProtocolVersion: SMBProtocol?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        type: MediaSourceType,
        url: URL,
        isEnabled: Bool = true,
        dateAdded: Date = Date(),
        username: String? = nil,
        bookmarkData: Data? = nil,
        allowInvalidCertificates: Bool = false,
        smbWorkgroup: String? = nil,
        smbProtocolVersion: SMBProtocol? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.url = url
        self.isEnabled = isEnabled
        self.dateAdded = dateAdded
        self.username = username
        self.bookmarkData = bookmarkData
        self.allowInvalidCertificates = allowInvalidCertificates
        self.smbWorkgroup = smbWorkgroup
        self.smbProtocolVersion = smbProtocolVersion
    }

    // MARK: - Factory Methods

    /// Creates a WebDAV media source.
    static func webdav(
        name: String,
        url: URL,
        username: String? = nil,
        allowInvalidCertificates: Bool = false
    ) -> MediaSource {
        MediaSource(
            name: name,
            type: .webdav,
            url: url,
            username: username,
            allowInvalidCertificates: allowInvalidCertificates
        )
    }

    /// Creates a local folder media source.
    static func localFolder(
        name: String,
        url: URL,
        bookmarkData: Data? = nil
    ) -> MediaSource {
        MediaSource(
            name: name,
            type: .localFolder,
            url: url,
            bookmarkData: bookmarkData
        )
    }

    /// Creates an SMB/CIFS media source.
    static func smb(
        name: String,
        url: URL,
        username: String? = nil,
        workgroup: String? = nil,
        protocolVersion: SMBProtocol? = nil
    ) -> MediaSource {
        MediaSource(
            name: name,
            type: .smb,
            url: url,
            username: username,
            smbWorkgroup: workgroup,
            smbProtocolVersion: protocolVersion
        )
    }

    // MARK: - Computed Properties

    /// Display string for the source URL.
    var urlDisplayString: String {
        switch type {
        case .webdav:
            return url.host ?? url.absoluteString
        case .localFolder:
            return url.lastPathComponent
        case .smb:
            return url.host ?? url.absoluteString
        }
    }

    /// Whether this source requires authentication.
    var requiresAuthentication: Bool {
        (type == .webdav || type == .smb) && username != nil
    }
}

// MARK: - Video Extension for Media Source Detection

extension Video {
    /// Whether this video is from a local folder media source (device-specific).
    var isFromLocalFolder: Bool {
        if case .extracted(let extractor, _) = id.source {
            return extractor == MediaFile.localFolderProvider
        }
        return false
    }

    /// Whether this video is from a WebDAV media source.
    var isFromWebDAV: Bool {
        if case .extracted(let extractor, _) = id.source {
            return extractor == MediaFile.webdavProvider
        }
        return false
    }

    /// Whether this video is from an SMB media source.
    var isFromSMB: Bool {
        if case .extracted(let extractor, _) = id.source {
            return extractor == MediaFile.smbProvider
        }
        return false
    }

    /// Whether this video is from any media source (WebDAV, SMB, or local folder).
    var isFromMediaSource: Bool {
        if case .extracted(let extractor, _) = id.source {
            return extractor == MediaFile.webdavProvider 
                || extractor == MediaFile.localFolderProvider
                || extractor == MediaFile.smbProvider
        }
        return false
    }

    /// Returns the media source UUID if this video is from any media source (WebDAV, SMB, or local folder).
    /// The videoID format is "sourceUUID:path/to/file".
    var mediaSourceID: UUID? {
        guard isFromMediaSource else { return nil }
        // videoID format: "sourceUUID:path"
        let components = id.videoID.split(separator: ":", maxSplits: 1)
        guard let uuidString = components.first else { return nil }
        return UUID(uuidString: String(uuidString))
    }

    /// Returns the file path if this video is from a media source.
    /// The videoID format is "sourceUUID:path/to/file".
    var mediaSourceFilePath: String? {
        guard isFromMediaSource else { return nil }
        let components = id.videoID.split(separator: ":", maxSplits: 1)
        guard components.count == 2 else { return nil }
        return String(components[1])
    }
}
