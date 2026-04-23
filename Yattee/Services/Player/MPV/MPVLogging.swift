//
//  MPVLogging.swift
//  Yattee
//
//  Centralized MPV rendering diagnostic logging.
//  Logs to Console (print) AND LoggingService for persistence.
//

import Foundation
#if os(iOS) || os(tvOS)
import OpenGLES
#elseif os(macOS)
import OpenGL
#endif

/// Centralized MPV rendering diagnostic logging.
/// Use this to diagnose rare rendering issues (black/green screen while audio plays).
enum MPVLogging {
    // MARK: - Setting Check

    /// Thread-safe cached check for verbose logging setting.
    /// Uses atomic operations for thread safety without locks.
    private static var _cachedIsEnabled: Bool = false
    private static var _lastCheckTime: UInt64 = 0
    private static let cacheDurationNanos: UInt64 = 1_000_000_000 // 1 second

    /// Check if verbose logging is enabled (cached for performance).
    /// Safe to call from any thread.
    private static func isEnabled() -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds

        // Refresh cache every second
        if now - _lastCheckTime > cacheDurationNanos {
            _lastCheckTime = now
            // Read from UserDefaults directly for thread safety
            // (SettingsManager is @MainActor)
            _cachedIsEnabled = UserDefaults.standard.bool(forKey: "verboseMPVLogging")
        }

        return _cachedIsEnabled
    }

    // MARK: - Logging Functions

    /// Log a verbose MPV rendering diagnostic message.
    /// Only logs if verbose MPV logging is enabled in settings.
    /// Thread-safe and can be called from any queue.
    ///
    /// - Parameters:
    ///   - message: The main log message
    ///   - details: Optional additional details
    ///   - file: Source file (auto-captured)
    ///   - function: Function name (auto-captured)
    ///   - line: Line number (auto-captured)
    static func log(
        _ message: String,
        details: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled() else { return }

        let timestamp = Self.timestamp()
        let threadName = Self.threadName()
        let fileName = (file as NSString).lastPathComponent

        let fullMessage = "[MPV-Verbose] [\(timestamp)] [\(threadName)] \(message)"

        // Log to Console immediately (thread-safe)
        print(fullMessage)
        if let details {
            print("  \(details)")
        }
        print("  [\(fileName):\(line) \(function)]")

        // Log to LoggingService on MainActor for persistence
        let logDetails = details.map { "\($0)\n[\(fileName):\(line) \(function)]" }
            ?? "[\(fileName):\(line) \(function)]"

        Task { @MainActor in
            LoggingService.shared.log(
                level: .debug,
                category: .mpv,
                message: "[MPV-Verbose] \(message)",
                details: logDetails
            )
        }
    }

    /// Log with warning level for potential issues.
    static func warn(
        _ message: String,
        details: String? = nil,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled() else { return }

        let timestamp = Self.timestamp()
        let threadName = Self.threadName()
        let fileName = (file as NSString).lastPathComponent

        let fullMessage = "[MPV-Verbose] ⚠️ \(timestamp)] [\(threadName)] \(message)"

        print(fullMessage)
        if let details {
            print("  \(details)")
        }
        print("  [\(fileName):\(line) \(function)]")

        let logDetails = details.map { "\($0)\n[\(fileName):\(line) \(function)]" }
            ?? "[\(fileName):\(line) \(function)]"

        Task { @MainActor in
            LoggingService.shared.log(
                level: .warning,
                category: .mpv,
                message: "[MPV-Verbose] \(message)",
                details: logDetails
            )
        }
    }

    /// Log OpenGL/EAGL state for debugging context and framebuffer issues.
    ///
    /// - Parameters:
    ///   - prefix: Description of the operation (e.g., "createFramebuffer")
    ///   - framebuffer: The framebuffer ID
    ///   - renderbuffer: The renderbuffer ID
    ///   - width: Framebuffer width
    ///   - height: Framebuffer height
    ///   - contextCurrent: Whether the GL context is current
    ///   - framebufferComplete: Whether the framebuffer is complete (nil if not checked)
    static func logGLState(
        _ prefix: String,
        framebuffer: UInt32,
        renderbuffer: UInt32,
        width: Int32,
        height: Int32,
        contextCurrent: Bool,
        framebufferComplete: Bool? = nil
    ) {
        var state = "FB:\(framebuffer) RB:\(renderbuffer) \(width)x\(height) ctx:\(contextCurrent ? "✓" : "✗")"
        if let complete = framebufferComplete {
            state += " complete:\(complete ? "✓" : "✗")"
        }

        log("\(prefix): \(state)")
    }

    /// Log display link state changes.
    ///
    /// - Parameters:
    ///   - action: The action being performed (e.g., "start", "stop", "pause")
    ///   - isPaused: Current paused state
    ///   - targetFPS: Target frame rate if applicable
    ///   - reason: Optional reason for the action
    static func logDisplayLink(
        _ action: String,
        isPaused: Bool? = nil,
        targetFPS: Double? = nil,
        reason: String? = nil
    ) {
        var details: [String] = []
        if let isPaused {
            details.append("paused:\(isPaused)")
        }
        if let targetFPS {
            details.append("targetFPS:\(String(format: "%.1f", targetFPS))")
        }
        if let reason {
            details.append("reason:\(reason)")
        }

        let detailsStr = details.isEmpty ? nil : details.joined(separator: " ")
        log("DisplayLink \(action)", details: detailsStr)
    }

    /// Log view lifecycle events.
    ///
    /// - Parameters:
    ///   - event: The lifecycle event (e.g., "willMove(toSuperview:)", "didMoveToSuperview")
    ///   - hasSuperview: Whether the view has a superview after the event
    ///   - details: Additional context
    static func logViewLifecycle(
        _ event: String,
        hasSuperview: Bool,
        details: String? = nil
    ) {
        log("View \(event)", details: "hasSuperview:\(hasSuperview)" + (details.map { " \($0)" } ?? ""))
    }

    /// Log app lifecycle / scene phase transitions.
    ///
    /// - Parameters:
    ///   - event: The lifecycle event
    ///   - isPiPActive: Whether PiP is currently active
    ///   - isRendering: Whether rendering is active
    static func logAppLifecycle(
        _ event: String,
        isPiPActive: Bool? = nil,
        isRendering: Bool? = nil
    ) {
        var details: [String] = []
        if let isPiPActive {
            details.append("pip:\(isPiPActive)")
        }
        if let isRendering {
            details.append("rendering:\(isRendering)")
        }

        let detailsStr = details.isEmpty ? nil : details.joined(separator: " ")
        log("App \(event)", details: detailsStr)
    }

    /// Log rotation and fullscreen transitions.
    ///
    /// - Parameters:
    ///   - event: The transition event
    ///   - fromOrientation: Previous orientation if applicable
    ///   - toOrientation: Target orientation if applicable
    static func logTransition(
        _ event: String,
        fromSize: CGSize? = nil,
        toSize: CGSize? = nil
    ) {
        var details: [String] = []
        if let fromSize {
            details.append("from:\(Int(fromSize.width))x\(Int(fromSize.height))")
        }
        if let toSize {
            details.append("to:\(Int(toSize.width))x\(Int(toSize.height))")
        }

        let detailsStr = details.isEmpty ? nil : details.joined(separator: " ")
        log("Transition \(event)", details: detailsStr)
    }

    /// Log render operations (use sparingly to avoid log spam).
    ///
    /// - Parameters:
    ///   - event: The render event
    ///   - fbo: Framebuffer being rendered to
    ///   - width: Render width
    ///   - height: Render height
    ///   - success: Whether the operation succeeded
    static func logRender(
        _ event: String,
        fbo: Int32? = nil,
        width: Int32? = nil,
        height: Int32? = nil,
        success: Bool? = nil
    ) {
        var details: [String] = []
        if let fbo {
            details.append("fbo:\(fbo)")
        }
        if let width, let height {
            details.append("\(width)x\(height)")
        }
        if let success {
            details.append(success ? "✓" : "✗")
        }

        let detailsStr = details.isEmpty ? nil : details.joined(separator: " ")
        log("Render \(event)", details: detailsStr)
    }

    // MARK: - Private Helpers

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private static func threadName() -> String {
        if Thread.isMainThread {
            return "main"
        }
        if let name = Thread.current.name, !name.isEmpty {
            return name
        }
        // Get queue label if available
        let label = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8) ?? "unknown"
        return label
    }
}
