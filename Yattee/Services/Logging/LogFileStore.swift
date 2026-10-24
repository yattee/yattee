//
//  LogFileStore.swift
//  Yattee
//
//  Persists log entries to disk so a session's logs survive the app being
//  killed and can be exported on the next launch.
//

import Foundation

/// Appends log entries to a per-session file in Caches/Logs.
///
/// The first use in a process rotates the last session's file to
/// `previous-session.log`, so the export after a relaunch still contains the
/// session that was killed. All file access happens on a private serial queue.
final class LogFileStore: @unchecked Sendable {
    static let shared = LogFileStore()

    /// Stop writing a session once it reaches this size.
    private static let maxSessionBytes = 25 * 1024 * 1024

    private let queue = DispatchQueue(label: "stream.yattee.logfile", qos: .utility)
    private let currentURL: URL
    private let previousURL: URL
    private var handle: FileHandle?
    private var bytesWritten = 0
    private var reachedLimit = false

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        currentURL = directory.appendingPathComponent("current-session.log")
        previousURL = directory.appendingPathComponent("previous-session.log")

        queue.async { [self] in
            let fileManager = FileManager.default
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: currentURL.path) {
                try? fileManager.removeItem(at: previousURL)
                try? fileManager.moveItem(at: currentURL, to: previousURL)
            }
            fileManager.createFile(atPath: currentURL.path, contents: nil)
            handle = try? FileHandle(forWritingTo: currentURL)
            write("Session started: pid \(ProcessInfo.processInfo.processIdentifier), "
                + "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") "
                + "(\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))\n")
        }
    }

    func append(_ entry: LogEntry) {
        queue.async { [self] in
            let details = entry.details.map { "\n  Details: \($0)" } ?? ""
            write("[\(formatter.string(from: entry.timestamp))] [\(entry.level.rawValue.uppercased())] "
                + "[\(entry.category.rawValue)] \(entry.message)\(details)\n")
        }
    }

    /// The previous session's log, or nil when there is none.
    func previousSessionText() -> String? {
        queue.sync {
            guard let data = try? Data(contentsOf: previousURL) else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
    }

    func clear() {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: previousURL)
            try? handle?.truncate(atOffset: 0)
            bytesWritten = 0
            reachedLimit = false
        }
    }

    /// Must be called on `queue`.
    private func write(_ line: String) {
        guard let handle, !reachedLimit else { return }
        let data = Data(line.utf8)
        if bytesWritten + data.count > Self.maxSessionBytes {
            reachedLimit = true
            try? handle.write(contentsOf: Data("--- log size limit reached, further entries not written ---\n".utf8))
            return
        }
        try? handle.write(contentsOf: data)
        bytesWritten += data.count
    }
}
