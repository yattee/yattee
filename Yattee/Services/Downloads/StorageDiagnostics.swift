//
//  StorageDiagnostics.swift
//  Yattee
//
//  Storage diagnostics and utilities for downloads.
//

import Foundation

// MARK: - Storage Diagnostics

/// Represents storage usage for a specific directory or category.
struct StorageUsageItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let fileCount: Int
}

/// Comprehensive storage diagnostics for debugging app storage usage.
struct StorageDiagnostics {
    let items: [StorageUsageItem]
    let totalSize: Int64
    let documentsSize: Int64
    let cachesSize: Int64
    let appSupportSize: Int64
    let tempSize: Int64
    let otherSize: Int64

    var formattedTotal: String { formatBytes(totalSize) }
    var formattedDocuments: String { formatBytes(documentsSize) }
    var formattedCaches: String { formatBytes(cachesSize) }
    var formattedAppSupport: String { formatBytes(appSupportSize) }
    var formattedTemp: String { formatBytes(tempSize) }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @MainActor
    func logDiagnostics() {
        LoggingService.shared.logDownload(
            "=== COMPREHENSIVE STORAGE DIAGNOSTICS ===",
            details: """
            Total app storage: \(formattedTotal)
            Documents: \(formattedDocuments)
            Caches: \(formattedCaches)
            Application Support: \(formattedAppSupport)
            Temp: \(formattedTemp)
            """
        )

        LoggingService.shared.logDownload("=== STORAGE BREAKDOWN ===")
        for item in items.sorted(by: { $0.size > $1.size }) {
            let formatted = formatBytes(item.size)
            LoggingService.shared.logDownload(
                "\(item.name): \(formatted)",
                details: "Files: \(item.fileCount), Path: \(item.path)"
            )
        }
    }
}

/// Helper to format bytes (standalone function for use in scanAppStorage)
private func formatBytesStatic(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
}

/// Scans all app directories and returns comprehensive storage diagnostics.
@MainActor
func scanAppStorage() -> StorageDiagnostics {
    let fileManager = FileManager.default
    var items: [StorageUsageItem] = []

    // Helper to calculate directory size (including hidden files)
    func directorySize(at url: URL, includeHidden: Bool = false) -> (size: Int64, count: Int) {
        var totalSize: Int64 = 0
        var fileCount = 0

        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .totalFileAllocatedSizeKey],
            options: options
        ) else {
            return (0, 0)
        }

        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .totalFileAllocatedSizeKey]),
                  resourceValues.isDirectory != true else {
                continue
            }
            // Use allocated size if available (accounts for sparse files and actual disk usage)
            let size = Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0)
            totalSize += size
            fileCount += 1
        }

        return (totalSize, fileCount)
    }

    // Documents directory
    var documentsTotal: Int64 = 0
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        // Downloads subfolder
        let downloadsURL = documentsURL.appendingPathComponent("Downloads")
        if fileManager.fileExists(atPath: downloadsURL.path) {
            let (size, count) = directorySize(at: downloadsURL)
            items.append(StorageUsageItem(name: "Downloads", path: downloadsURL.path, size: size, fileCount: count))
            documentsTotal += size
        }

        // Check for other items in Documents
        if let contents = try? fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil) {
            for item in contents where item.lastPathComponent != "Downloads" {
                let (size, count) = directorySize(at: item)
                if size > 0 {
                    items.append(StorageUsageItem(name: "Documents/\(item.lastPathComponent)", path: item.path, size: size, fileCount: count))
                    documentsTotal += size
                }
            }
        }
    }

    // Caches directory
    var cachesTotal: Int64 = 0
    if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
        // Image cache
        let imageCacheURL = cachesURL.appendingPathComponent("ImageCache")
        if fileManager.fileExists(atPath: imageCacheURL.path) {
            let (size, count) = directorySize(at: imageCacheURL)
            items.append(StorageUsageItem(name: "Image Cache", path: imageCacheURL.path, size: size, fileCount: count))
            cachesTotal += size
        }

        // Feed cache
        let feedCacheURL = cachesURL.appendingPathComponent("FeedCache")
        if fileManager.fileExists(atPath: feedCacheURL.path) {
            let (size, count) = directorySize(at: feedCacheURL)
            items.append(StorageUsageItem(name: "Feed Cache", path: feedCacheURL.path, size: size, fileCount: count))
            cachesTotal += size
        }

        // URLSession cache (com.apple.nsurlsessiond)
        if let contents = try? fileManager.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil) {
            for item in contents {
                let name = item.lastPathComponent
                if name == "ImageCache" || name == "FeedCache" { continue }

                let (size, count) = directorySize(at: item)
                if size > 1024 { // Only show if > 1KB
                    items.append(StorageUsageItem(name: "Caches/\(name)", path: item.path, size: size, fileCount: count))
                    cachesTotal += size
                }
            }
        }
    }

    // Application Support directory
    var appSupportTotal: Int64 = 0
    if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        if let contents = try? fileManager.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil) {
            for item in contents {
                let (size, count) = directorySize(at: item)
                if size > 1024 { // Only show if > 1KB
                    items.append(StorageUsageItem(name: "AppSupport/\(item.lastPathComponent)", path: item.path, size: size, fileCount: count))
                    appSupportTotal += size
                }
            }
        }
    }

    // Temp directory
    var tempTotal: Int64 = 0
    let tempURL = fileManager.temporaryDirectory
    if let contents = try? fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil) {
        for item in contents {
            let (size, count) = directorySize(at: item)
            if size > 1024 { // Only show if > 1KB
                items.append(StorageUsageItem(name: "Temp/\(item.lastPathComponent)", path: item.path, size: size, fileCount: count))
                tempTotal += size
            }
        }
    }

    // Library directory - scan ALL subdirectories to find hidden storage
    var otherTotal: Int64 = 0
    if let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
        // Get all items in Library (including hidden)
        if let contents = try? fileManager.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: nil, options: []) {
            for item in contents {
                let name = item.lastPathComponent
                // Skip Caches (already scanned) and Application Support (already scanned)
                if name == "Caches" || name == "Application Support" { continue }

                let (size, count) = directorySize(at: item, includeHidden: true)
                if size > 1024 { // Only show if > 1KB
                    items.append(StorageUsageItem(name: "Library/\(name)", path: item.path, size: size, fileCount: count))
                    otherTotal += size
                }
            }
        }
    }

    // Check the app container root for anything we might have missed
    // Go up from Documents to the container root
    if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let containerURL = documentsURL.deletingLastPathComponent()

        // Scan for any top-level directories we haven't covered
        if let contents = try? fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: []) {
            for item in contents {
                let name = item.lastPathComponent
                // Skip directories we've already scanned
                if name == "Documents" || name == "Library" || name == "tmp" || name == "SystemData" { continue }

                let (size, count) = directorySize(at: item, includeHidden: true)
                if size > 1024 {
                    items.append(StorageUsageItem(name: "Container/\(name)", path: item.path, size: size, fileCount: count))
                    otherTotal += size
                }
            }
        }

        // Log the container path for reference
        LoggingService.shared.logDownload("App Container", details: containerURL.path)

        // Scan ENTIRE container recursively to find all storage
        let (totalContainerSize, totalContainerFiles) = directorySize(at: containerURL, includeHidden: true)
        LoggingService.shared.logDownload(
            "TOTAL Data Container: \(formatBytesStatic(totalContainerSize))",
            details: "\(totalContainerFiles) files at \(containerURL.path)"
        )

        // Scan ALL top-level directories in container to find where storage is hiding
        LoggingService.shared.logDownload("=== CONTAINER BREAKDOWN ===")
        if let allContents = try? fileManager.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil, options: []) {
            for item in allContents {
                let (itemSize, itemCount) = directorySize(at: item, includeHidden: true)
                LoggingService.shared.logDownload(
                    "  \(item.lastPathComponent): \(formatBytesStatic(itemSize))",
                    details: "\(itemCount) files"
                )

                // If this is a large directory, scan its subdirectories too
                if itemSize > 100 * 1024 * 1024 { // > 100 MB
                    if let subContents = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: []) {
                        for subItem in subContents {
                            let (subSize, subCount) = directorySize(at: subItem, includeHidden: true)
                            if subSize > 10 * 1024 * 1024 { // > 10 MB
                                LoggingService.shared.logDownload(
                                    "    \(subItem.lastPathComponent): \(formatBytesStatic(subSize))",
                                    details: "\(subCount) files"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    // Check the app bundle size (this is read-only, can't be cleared)
    var bundleSize: Int64 = 0
    if let bundleURL = Bundle.main.bundleURL as URL? {
        let (size, count) = directorySize(at: bundleURL, includeHidden: true)
        bundleSize = size
        items.append(StorageUsageItem(name: "App Bundle (read-only)", path: bundleURL.path, size: size, fileCount: count))
        LoggingService.shared.logDownload("App Bundle", details: bundleURL.path)

        // Log contents of bundle for debugging
        if let contents = try? fileManager.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil, options: []) {
            for item in contents {
                let (itemSize, itemCount) = directorySize(at: item, includeHidden: true)
                if itemSize > 1024 * 1024 { // Only log items > 1MB
                    LoggingService.shared.logDownload("  Bundle/\(item.lastPathComponent): \(formatBytesStatic(itemSize))", details: "\(itemCount) files")
                }
            }
        }

        // Check parent of bundle for other app-related directories
        let bundleParent = bundleURL.deletingLastPathComponent()
        if let parentContents = try? fileManager.contentsOfDirectory(at: bundleParent, includingPropertiesForKeys: nil, options: []) {
            for item in parentContents where item.lastPathComponent != bundleURL.lastPathComponent {
                let (itemSize, itemCount) = directorySize(at: item, includeHidden: true)
                if itemSize > 1024 * 1024 { // Only log items > 1MB
                    items.append(StorageUsageItem(name: "BundleContainer/\(item.lastPathComponent)", path: item.path, size: itemSize, fileCount: itemCount))
                    bundleSize += itemSize
                    LoggingService.shared.logDownload("BundleContainer/\(item.lastPathComponent): \(formatBytesStatic(itemSize))", details: "\(itemCount) files")
                }
            }
        }
        LoggingService.shared.logDownload("Bundle container", details: bundleParent.path)
    }

    let totalSize = documentsTotal + cachesTotal + appSupportTotal + tempTotal + otherTotal + bundleSize

    return StorageDiagnostics(
        items: items,
        totalSize: totalSize,
        documentsSize: documentsTotal,
        cachesSize: cachesTotal,
        appSupportSize: appSupportTotal,
        tempSize: tempTotal,
        otherSize: otherTotal
    )
}

// MARK: - Thread-Safe Storage

/// A thread-safe wrapper for mutable values using NSLock.
/// Conforms to Sendable since all access is synchronized.
final class LockedStorage<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func read<T>(_ block: (Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block(value)
    }

    func write(_ block: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        block(&value)
    }
}
