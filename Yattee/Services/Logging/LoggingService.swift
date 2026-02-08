//
//  LoggingService.swift
//  Yattee
//
//  Centralized logging service for in-app log viewing.
//

import Foundation
import OSLog

/// Log entry severity level.
enum LogLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error

    var icon: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}

/// Log entry category.
enum LogCategory: String, Codable, CaseIterable, Sendable {
    case api = "API"
    case player = "Player"
    case mpv = "MPV"
    case cloudKit = "CloudKit"
    case downloads = "Downloads"
    case navigation = "Navigation"
    case notifications = "Notifications"
    case remoteControl = "RemoteControl"
    case keychain = "Keychain"
    case imageLoading = "ImageLoading"
    case mediaSources = "MediaSources"
    case subscriptions = "Subscriptions"
    case general = "General"

    var icon: String {
        switch self {
        case .api: return "network"
        case .player: return "play.circle"
        case .mpv: return "film"
        case .cloudKit: return "icloud"
        case .downloads: return "arrow.down.circle"
        case .navigation: return "arrow.triangle.turn.up.right.diamond"
        case .notifications: return "bell.badge"
        case .remoteControl: return "appletvremote.gen4"
        case .keychain: return "key.fill"
        case .imageLoading: return "photo"
        case .mediaSources: return "externaldrive.connected.to.line.below"
        case .subscriptions: return "person.2"
        case .general: return "doc.text"
        }
    }
}

/// A single log entry.
struct LogEntry: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let details: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        details: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.details = details
    }

    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Centralized logging service for in-app log viewing.
@MainActor
@Observable
final class LoggingService: Sendable {
    // MARK: - Singleton

    /// Shared singleton instance accessible from any isolation context.
    /// Safe because instance logging methods are nonisolated (thread-safe via Task dispatch to MainActor).
    nonisolated static let shared: LoggingService = {
        MainActor.assumeIsolated {
            LoggingService()
        }
    }()

    // MARK: - Properties

    /// Whether logging is enabled.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "loggingEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "loggingEnabled")
            if !newValue {
                entries.removeAll()
            }
        }
    }

    /// Maximum number of log entries to keep.
    var maxEntries: Int = 5000

    /// All log entries.
    private(set) var entries: [LogEntry] = []

    /// Filtered entries based on current filter settings.
    var filteredEntries: [LogEntry] {
        var result = entries

        if !selectedCategories.isEmpty {
            result = result.filter { selectedCategories.contains($0.category) }
        }

        if !selectedLevels.isEmpty {
            result = result.filter { selectedLevels.contains($0.level) }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                ($0.details?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    /// Filter: selected categories.
    var selectedCategories: Set<LogCategory> = []

    /// Filter: selected levels.
    var selectedLevels: Set<LogLevel> = []

    /// Filter: search text.
    var searchText: String = ""

    // MARK: - Private

    /// OSLogger instance. Logger is Sendable and thread-safe internally.
    private let osLogger = Logger(subsystem: AppIdentifiers.logSubsystem, category: "LoggingService")

    // MARK: - Initialization

    private init() {}

    // MARK: - Logging Methods

    /// Log a debug message.
    nonisolated func debug(_ message: String, category: LogCategory = .general, details: String? = nil) {
        log(level: .debug, category: category, message: message, details: details)
    }

    /// Log an info message.
    nonisolated func info(_ message: String, category: LogCategory = .general, details: String? = nil) {
        log(level: .info, category: category, message: message, details: details)
    }

    /// Log a warning message.
    nonisolated func warning(_ message: String, category: LogCategory = .general, details: String? = nil) {
        log(level: .warning, category: category, message: message, details: details)
    }

    /// Log an error message.
    nonisolated func error(_ message: String, category: LogCategory = .general, details: String? = nil) {
        log(level: .error, category: category, message: message, details: details)
    }

    /// Log a message with the specified level.
    /// This method is nonisolated to allow safe logging from any thread.
    /// OSLog output is synchronous; in-app storage is dispatched to MainActor.
    nonisolated func log(level: LogLevel, category: LogCategory, message: String, details: String? = nil) {
        // Log to OSLog in DEBUG builds for Xcode console visibility
        // OSLog/Logger is thread-safe, so this can be called from any thread
        #if DEBUG
        let fullMessage = details.map { "\(message) - \($0)" } ?? message
        switch level {
        case .debug:
            osLogger.debug("[\(category.rawValue)] \(fullMessage)")
        case .info:
            osLogger.info("[\(category.rawValue)] \(fullMessage)")
        case .warning:
            osLogger.warning("[\(category.rawValue)] \(fullMessage)")
        case .error:
            osLogger.error("[\(category.rawValue)] \(fullMessage)")
        }
        #endif

        // Dispatch in-app storage to MainActor asynchronously
        // This ensures thread-safety for the entries array
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isEnabled else { return }

            let entry = LogEntry(
                level: level,
                category: category,
                message: message,
                details: details
            )

            self.entries.insert(entry, at: 0)

            // Trim old entries
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
        }
    }

    // MARK: - Management

    /// Clear all log entries.
    func clearLogs() {
        entries.removeAll()
    }

    /// Export logs as text.
    func exportLogs() -> String {
        let header = "Yattee Logs - Exported \(Date().formatted())\n"
        let separator = String(repeating: "=", count: 60) + "\n"

        let logLines = entries.reversed().map { entry in
            let details = entry.details.map { "\n  Details: \($0)" } ?? ""
            return "[\(entry.formattedTimestamp)] [\(entry.level.rawValue.uppercased())] [\(entry.category.rawValue)] \(entry.message)\(details)"
        }.joined(separator: "\n")

        return header + separator + logLines
    }

    /// Reset filters.
    func resetFilters() {
        selectedCategories = []
        selectedLevels = []
        searchText = ""
    }
}

// MARK: - Convenience Extensions

extension LoggingService {
    /// Log an API request.
    nonisolated func logAPIRequest(_ method: String, url: URL, details: String? = nil) {
        info("\(method) \(url.absoluteString)", category: .api, details: details)
    }

    /// Log an API response.
    nonisolated func logAPIResponse(_ url: URL, statusCode: Int, duration: TimeInterval) {
        let durationMs = Int(duration * 1000)
        info("Response \(statusCode) from \(url.host ?? url.absoluteString) (\(durationMs)ms)", category: .api)
    }

    /// Log an API error.
    nonisolated func logAPIError(_ url: URL, error: Error) {
        self.error("API Error: \(url.absoluteString)", category: .api, details: error.localizedDescription)
    }

    /// Log a player event.
    nonisolated func logPlayer(_ message: String, details: String? = nil) {
        info(message, category: .player, details: details)
    }

    /// Log a player error.
    nonisolated func logPlayerError(_ message: String, error: Error? = nil) {
        self.error(message, category: .player, details: error?.localizedDescription)
    }

    /// Log a CloudKit event.
    nonisolated func logCloudKit(_ message: String, details: String? = nil) {
        info(message, category: .cloudKit, details: details)
    }

    /// Log a CloudKit error.
    nonisolated func logCloudKitError(_ message: String, error: Error? = nil) {
        self.error(message, category: .cloudKit, details: error?.localizedDescription)
    }

    /// Log a download event.
    nonisolated func logDownload(_ message: String, details: String? = nil) {
        info(message, category: .downloads, details: details)
    }

    /// Log a download error.
    nonisolated func logDownloadError(_ message: String, error: Error? = nil) {
        self.error(message, category: .downloads, details: error?.localizedDescription)
    }

    /// Log a notification event.
    nonisolated func logNotification(_ message: String, details: String? = nil) {
        info(message, category: .notifications, details: details)
    }

    /// Log a notification error.
    nonisolated func logNotificationError(_ message: String, error: Error? = nil) {
        self.error(message, category: .notifications, details: error?.localizedDescription)
    }

    /// Log a remote control event.
    nonisolated func logRemoteControl(_ message: String, details: String? = nil) {
        info(message, category: .remoteControl, details: details)
    }

    /// Log a remote control warning.
    nonisolated func logRemoteControlWarning(_ message: String, details: String? = nil) {
        warning(message, category: .remoteControl, details: details)
    }

    /// Log a remote control error.
    nonisolated func logRemoteControlError(_ message: String, error: Error? = nil) {
        self.error(message, category: .remoteControl, details: error?.localizedDescription)
    }

    /// Log a remote control debug message.
    nonisolated func logRemoteControlDebug(_ message: String, details: String? = nil) {
        debug(message, category: .remoteControl, details: details)
    }

    /// Log an MPV event.
    nonisolated func logMPV(_ message: String, details: String? = nil) {
        info(message, category: .mpv, details: details)
    }

    /// Log an MPV debug message.
    nonisolated func logMPVDebug(_ message: String, details: String? = nil) {
        debug(message, category: .mpv, details: details)
    }

    /// Log an MPV warning.
    nonisolated func logMPVWarning(_ message: String, details: String? = nil) {
        warning(message, category: .mpv, details: details)
    }

    /// Log an MPV error.
    nonisolated func logMPVError(_ message: String, error: Error? = nil) {
        self.error(message, category: .mpv, details: error?.localizedDescription)
    }

    // MARK: - Media Sources Logging

    /// Log a media sources event.
    nonisolated func logMediaSources(_ message: String, details: String? = nil) {
        info(message, category: .mediaSources, details: details)
    }

    /// Log a media sources error.
    nonisolated func logMediaSourcesError(_ message: String, error: Error? = nil) {
        self.error(message, category: .mediaSources, details: error?.localizedDescription)
    }

    /// Log a media sources debug message.
    nonisolated func logMediaSourcesDebug(_ message: String, details: String? = nil) {
        debug(message, category: .mediaSources, details: details)
    }

    /// Log a media sources warning.
    nonisolated func logMediaSourcesWarning(_ message: String, details: String? = nil) {
        warning(message, category: .mediaSources, details: details)
    }

    // MARK: - Subscriptions Logging

    /// Log a subscriptions event.
    nonisolated func logSubscriptions(_ message: String, details: String? = nil) {
        info(message, category: .subscriptions, details: details)
    }

    /// Log a subscriptions error.
    nonisolated func logSubscriptionsError(_ message: String, error: Error? = nil) {
        self.error(message, category: .subscriptions, details: error?.localizedDescription)
    }
}
