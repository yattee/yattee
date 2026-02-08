//
//  SMBBridgeWrapper.swift
//  Yattee
//
//  Swift wrapper around libsmbclient C bridge for directory browsing.
//

import Foundation

/// Swift wrapper for SMB file information from C bridge.
struct SMBFileEntry: Sendable {
    let name: String
    let isDirectory: Bool
    let isShare: Bool  // True if this is an SMB file share (SMBC_FILE_SHARE)
    let size: Int64
    let modifiedDate: Date?
    let createdDate: Date?
}

/// Error types for SMB bridge operations.
enum SMBBridgeError: Error, LocalizedError, Sendable {
    case contextInitFailed
    case connectionFailed(String)
    case listingFailed(String)
    case invalidURL
    case invalidParameters
    
    var errorDescription: String? {
        switch self {
        case .contextInitFailed:
            return "Failed to initialize SMB context"
        case .connectionFailed(let msg):
            return "SMB connection failed: \(msg)"
        case .listingFailed(let msg):
            return "Failed to list directory: \(msg)"
        case .invalidURL:
            return "Invalid SMB URL"
        case .invalidParameters:
            return "Invalid parameters provided"
        }
    }
    
    /// User-friendly error messages based on common SMB errors
    var userFriendlyMessage: String {
        switch self {
        case .connectionFailed(let msg) where msg.contains("errno: 13"):
            return "Permission denied. Check username and password."
        case .connectionFailed(let msg) where msg.contains("errno: 2"):
            return "Share or path not found."
        case .connectionFailed(let msg) where msg.contains("errno: 110"):
            return "Connection timed out. Check server address and network."
        case .connectionFailed(let msg) where msg.contains("errno: 111"):
            return "Cannot reach server. Check server address."
        case .listingFailed(let msg) where msg.contains("errno: 13"):
            return "Access denied to this folder."
        default:
            return errorDescription ?? "Unknown error"
        }
    }
}

/// SMB protocol version for connection preferences (Swift wrapper).
enum SMBProtocol: Int32, Codable, Hashable, Sendable, CaseIterable {
    case auto = 0
    case smb1 = 1
    case smb2 = 2
    case smb3 = 3

    /// Display name for UI
    var displayName: String {
        switch self {
        case .auto: return String(localized: "smb.protocol.auto")
        case .smb1: return "SMB1"
        case .smb2: return "SMB2"
        case .smb3: return "SMB3"
        }
    }

    /// Convert to C enum type
    var cValue: SMBProtocolVersion {
        SMBProtocolVersion(UInt32(rawValue))
    }
}

/// Thread-safe wrapper around libsmbclient context.
actor SMBBridgeContext {
    private var context: UnsafeMutableRawPointer?
    private let workgroup: String
    private let username: String?
    private let password: String?
    private let protocolVersion: SMBProtocol
    
    init(workgroup: String = "WORKGROUP",
         username: String?,
         password: String?,
         protocolVersion: SMBProtocol = SMBProtocol.auto) {
        self.workgroup = workgroup
        self.username = username
        self.password = password
        self.protocolVersion = protocolVersion
    }
    
    /// Initialize the SMB context.
    func initialize() throws {
        guard context == nil else { return }

        LoggingService.shared.logMediaSourcesDebug("Initializing SMB context with workgroup: \(self.workgroup), protocol: \(self.protocolVersion.rawValue)")

        let wg = workgroup.cString(using: .utf8)
        let user = username?.cString(using: .utf8)
        let pass = password?.cString(using: .utf8)

        // Use the Swift enum's conversion to C enum type
        context = smb_init_context(wg, user, pass, protocolVersion.cValue)

        if context == nil {
            LoggingService.shared.logMediaSourcesError("Failed to initialize SMB context")
            throw SMBBridgeError.contextInitFailed
        }

        LoggingService.shared.logMediaSources("SMB context initialized successfully")
    }
    
    /// List directory contents at given SMB URL.
    func listDirectory(at url: String) throws -> [SMBFileEntry] {
        guard let context = context else {
            throw SMBBridgeError.contextInitFailed
        }

        LoggingService.shared.logMediaSourcesDebug("Listing SMB directory: \(url)")

        var count: Int32 = 0
        var errorPtr: UnsafeMutablePointer<CChar>?

        guard let fileList = smb_list_directory(context, url, &count, &errorPtr) else {
            let errorMsg = errorPtr.map { String(cString: $0) } ?? "Unknown error"
            if let errorPtr = errorPtr {
                free(errorPtr)
            }

            // Empty directory is not an error
            if count == 0 && errorMsg == "Unknown error" {
                LoggingService.shared.logMediaSourcesDebug("Directory is empty")
                return []
            }

            LoggingService.shared.logMediaSourcesError("Failed to list directory: \(errorMsg)")
            throw SMBBridgeError.listingFailed(errorMsg)
        }

        defer { smb_free_file_list(fileList, count) }

        var entries: [SMBFileEntry] = []

        for i in 0..<Int(count) {
            let fileInfo = fileList[i]
            let name = String(cString: fileInfo.name)

            // SMBC_FILE_SHARE = 3, SMBC_DIR = 7, SMBC_FILE = 8 (from libsmbclient.h)
            let isShare = fileInfo.type == 3
            let isDirectory = fileInfo.type == 7

            let modifiedDate = fileInfo.mtime > 0
                ? Date(timeIntervalSince1970: TimeInterval(fileInfo.mtime))
                : nil
            let createdDate = fileInfo.ctime > 0
                ? Date(timeIntervalSince1970: TimeInterval(fileInfo.ctime))
                : nil

            entries.append(SMBFileEntry(
                name: name,
                isDirectory: isDirectory,
                isShare: isShare,
                size: Int64(fileInfo.size),
                modifiedDate: modifiedDate,
                createdDate: createdDate
            ))
        }

        LoggingService.shared.logMediaSources("Listed \(entries.count) items from SMB directory")
        return entries
    }
    
    /// Test connection to SMB URL.
    func testConnection(to url: String) throws {
        guard let context = context else {
            throw SMBBridgeError.contextInitFailed
        }

        LoggingService.shared.logMediaSourcesDebug("Testing SMB connection to: \(url)")

        let result = smb_test_connection(context, url)
        if result != 0 {
            let errorMsg = "Connection test failed with error code: \(result)"
            LoggingService.shared.logMediaSourcesError(errorMsg)
            throw SMBBridgeError.connectionFailed(errorMsg)
        }

        LoggingService.shared.logMediaSources("SMB connection test succeeded")
    }
    
    /// Download file from SMB to local path.
    func downloadFile(from url: String, to localPath: String) throws {
        guard let context = context else {
            throw SMBBridgeError.contextInitFailed
        }

        LoggingService.shared.logMediaSourcesDebug("Downloading file from: \(url)")
        LoggingService.shared.logMediaSourcesDebug("Downloading file to: \(localPath)")

        var errorPtr: UnsafeMutablePointer<CChar>?
        let result = smb_download_file(context, url, localPath, &errorPtr)

        if result != 0 {
            let errorMsg = errorPtr.map { String(cString: $0) } ?? "Unknown error"
            if let errorPtr = errorPtr {
                free(errorPtr)
            }
            LoggingService.shared.logMediaSourcesError("Failed to download file: \(errorMsg)")
            throw SMBBridgeError.connectionFailed(errorMsg)
        }

        LoggingService.shared.logMediaSources("File download succeeded")
    }

    /// Clean up resources.
    deinit {
        if let context = context {
            smb_free_context(context)
            LoggingService.shared.logMediaSourcesDebug("SMB context cleaned up")
        }
    }
}
