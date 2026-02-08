//
//  DownloadError.swift
//  Yattee
//
//  Error types for download operations.
//

import Foundation

enum DownloadError: LocalizedError {
    case notSupported
    case alreadyDownloading
    case alreadyDownloaded
    case noStreamAvailable
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Downloads are not supported on this platform."
        case .alreadyDownloading:
            return "This video is already downloading."
        case .alreadyDownloaded:
            return "This video has already been downloaded."
        case .noStreamAvailable:
            return "No downloadable stream available."
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        }
    }
}
