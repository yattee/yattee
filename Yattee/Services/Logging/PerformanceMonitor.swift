//
//  PerformanceMonitor.swift
//  Yattee
//
//  Performance Logging: periodic resource usage with attribution, in the
//  foreground and the background, under the Performance log category.
//

import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
#if os(iOS) || os(macOS)
import MetricKit
#endif

/// Logs a resource sample every 5 seconds while Performance Logging is on:
/// CPU split by area and thread, wakeups, GPU, memory, disk, the
/// activity counters (`PerfCounter`) as rates, and app/player context.
/// Each foreground/background transition also logs a summary of the period
/// that just ended.
///
/// MetricKit reports (daily metrics, CPU exceptions, hangs) are logged
/// whenever logging is enabled, independent of the Performance toggle.
final class PerformanceMonitor: @unchecked Sendable {
    static let shared = PerformanceMonitor()
    static let enabledKey = "performanceLoggingEnabled"

    private static let interval: TimeInterval = 5
    /// Process CPU above these (percent of one core) logs the sample as a warning.
    private static let highCPUForeground = 60.0
    private static let highCPUBackground = 15.0

    // Confined to `queue`.
    private let queue = DispatchQueue(label: "stream.yattee.performance", qos: .utility)
    private var sampler: ResourceSampler?
    private var timer: DispatchSourceTimer?
    private var period: Period?
    private var context = ""
    private var isBackground = false

    // Main thread only.
    @MainActor private weak var appEnvironment: AppEnvironment?
    @MainActor private var runLoopObserver: CFRunLoopObserver?
    @MainActor private var started = false
    @MainActor private var batteryReference: (date: Date, level: Float)?
    #if os(iOS) || os(macOS)
    @MainActor private var metricSubscriber: MetricSubscriber?
    #endif

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    @MainActor
    func start(appEnvironment: AppEnvironment) {
        guard !started else { return }
        started = true
        self.appEnvironment = appEnvironment
        observeLifecycle()
        #if os(iOS) || os(macOS)
        let subscriber = MetricSubscriber()
        MXMetricManager.shared.add(subscriber)
        metricSubscriber = subscriber
        #endif
        if isEnabled {
            activate()
        }
    }

    @MainActor
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            activate()
        } else {
            deactivate()
        }
    }

    // MARK: - Activation

    @MainActor
    private func activate() {
        PerfCounter.setEnabled(true)
        installRunLoopObserver()
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif

        let mainThreadPort = pthread_mach_thread_np(pthread_self())
        let background = currentlyInBackground()
        let context = makeContext()
        queue.async {
            self.isBackground = background
            self.context = context
            let sampler = ResourceSampler(mainThreadPort: mainThreadPort)
            sampler.reset()
            self.sampler = sampler
            _ = PerfCounter.take()
            self.period = Period(background: background)

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .milliseconds(500))
            timer.setEventHandler { self.tick() }
            timer.resume()
            self.timer = timer

            self.log(.info, "Performance logging started", details: "context: " + context)
        }
    }

    @MainActor
    private func deactivate() {
        PerfCounter.setEnabled(false)
        if let runLoopObserver {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), runLoopObserver, .commonModes)
            self.runLoopObserver = nil
        }
        queue.async {
            self.timer?.cancel()
            self.timer = nil
            self.logPeriodSummary()
            self.period = nil
            self.sampler = nil
            self.log(.info, "Performance logging stopped", details: nil)
        }
    }

    @MainActor
    private func installRunLoopObserver() {
        guard runLoopObserver == nil else { return }
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, 0) { _, _ in
            PerfCounter.count("main.runLoopWakeup")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        runLoopObserver = observer
    }

    // MARK: - Lifecycle

    @MainActor
    private func observeLifecycle() {
        let center = NotificationCenter.default
        #if os(iOS) || os(tvOS)
        let transitions: [(Notification.Name, Bool)] = [
            (UIApplication.didEnterBackgroundNotification, true),
            (UIApplication.willEnterForegroundNotification, false),
        ]
        #elseif os(macOS)
        let transitions: [(Notification.Name, Bool)] = [
            (NSApplication.didResignActiveNotification, true),
            (NSApplication.didBecomeActiveNotification, false),
        ]
        #endif
        for (name, background) in transitions {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    PerformanceMonitor.shared.stateChanged(background: background)
                }
            }
        }
    }

    @MainActor
    private func stateChanged(background: Bool) {
        guard PerfCounter.enabled else { return }
        let context = makeContext()
        queue.async {
            guard self.sampler != nil, background != self.isBackground else { return }
            // Close the period at the transition with a final sample.
            self.takeSample()
            self.logPeriodSummary()
            self.context = context
            self.isBackground = background
            self.period = Period(background: background)
        }
    }

    // MARK: - Sampling

    private func tick() {
        takeSample()
        // Refresh the context for the next sample; the main thread may be
        // busy, so the sample itself never waits for it.
        DispatchQueue.main.async {
            let context = MainActor.assumeIsolated { self.makeContext() }
            self.queue.async { self.context = context }
        }
    }

    /// Must run on `queue`.
    private func takeSample() {
        guard let sampler else { return }
        let sample = sampler.sample()
        let counts = PerfCounter.take()
        guard sample.wall > 0 else { return }
        period?.add(sample, counts: counts)

        // A sample right after the previous one (at a transition) only feeds the period totals.
        guard sample.wall >= 1, UserDefaults.standard.bool(forKey: "loggingEnabled") else { return }

        let state = isBackground ? "bg" : "fg"
        let threshold = isBackground ? Self.highCPUBackground : Self.highCPUForeground
        let footprint = sample.footprintMB.map { "\($0)MB" } ?? "?"
        let wakeups = (sample.idleWakeupsPerSecond ?? 0) + (sample.interruptWakeupsPerSecond ?? 0)
        let message = String(format: "Perf [%@] cpu %.1f%% | %@ | wakeups %.0f/s | mem %@",
            state, sample.cpuPercent, sample.areasText, wakeups, footprint)

        var lines = [
            "threads: \(sample.hotThreadsText)",
            sample.powerText,
            String(format: "cpu: user %.1f%% system %.1f%% | %d threads | disk ops read %d write %d | window %.1fs",
                sample.userPercent, sample.systemPercent, sample.threadCount,
                sample.diskReadOps, sample.diskWriteOps, sample.wall),
        ]
        lines.append(contentsOf: Self.describeCounts(counts, over: sample.wall))
        lines.append("context: \(context)")

        log(sample.cpuPercent >= threshold ? .warning : .info, message, details: lines.joined(separator: "\n"))
    }

    /// Must run on `queue`.
    private func logPeriodSummary() {
        guard let period, period.wall > 0,
              UserDefaults.standard.bool(forKey: "loggingEnabled") else { return }
        let wall = period.wall
        let minutes = Int(wall) / 60
        let seconds = Int(wall) % 60
        let areas = period.areaSeconds.sorted { $0.value > $1.value }
            .map { String(format: "%@ %.1f", $0.key, $0.value / wall * 100) }
            .joined(separator: " ")

        var lines = [
            String(format: "cpu: avg %.1f%% max %.1f%% | %@", period.cpuSeconds / wall * 100, period.maxCPU, areas.isEmpty ? "idle" : areas),
            String(format: "wakeups: avg %.0f/s", period.wakeups / wall),
        ]
        lines.append(contentsOf: Self.describeCounts(period.counts, over: wall))
        lines.append("context: \(context)")

        log(.info, "Perf summary [\(period.background ? "bg" : "fg")] \(minutes)m \(seconds)s",
            details: lines.joined(separator: "\n"))
    }

    /// Counters as rates: views in their own line, everything else as "activity".
    private static func describeCounts(_ counts: [String: Int], over wall: TimeInterval) -> [String] {
        func format(_ entries: [(key: String, value: Int)], stripping prefix: String = "") -> String {
            entries.prefix(15).map { entry in
                let name = String(entry.key.dropFirst(prefix.count))
                if entry.key.hasSuffix(".bytes") {
                    return String(format: "%@ %.1fKB/s", name, Double(entry.value) / 1024 / wall)
                }
                return String(format: "%@ %.1f/s", name, Double(entry.value) / wall)
            }.joined(separator: ", ")
        }
        let sorted = counts.sorted { $0.value > $1.value }
        let views = sorted.filter { $0.key.hasPrefix("view.") }
        let activity = sorted.filter { !$0.key.hasPrefix("view.") }
        return [
            "activity: " + (activity.isEmpty ? "none" : format(activity)),
            "views: " + (views.isEmpty ? "none" : format(views, stripping: "view.")),
        ]
    }

    private func log(_ level: LogLevel, _ message: String, details: String?) {
        LoggingService.shared.log(level: level, category: .performance, message: message, details: details)
    }

    // MARK: - Context

    @MainActor
    private func currentlyInBackground() -> Bool {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.applicationState == .background
        #elseif os(macOS)
        !NSApplication.shared.isActive
        #endif
    }

    @MainActor
    private func makeContext() -> String {
        var parts: [String] = []

        #if os(iOS) || os(tvOS)
        let appState: String = switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
        parts.append("app \(appState)")
        #elseif os(macOS)
        parts.append("app \(NSApplication.shared.isActive ? "active" : "inactive")")
        #endif

        if let appEnvironment {
            let state = appEnvironment.playerService.state
            var player = "player \(state.playbackState)"
            if state.currentVideo != nil {
                player += state.currentStream?.isAudioOnly == true ? " audio-only" : " video"
                player += " pip=\(state.pipState)"
                player += " expanded=\(appEnvironment.navigationCoordinator.isPlayerExpanded)"
                player += " publishesTime=\(state.publishesTimeUpdates)"
            }
            parts.append(player)
        }

        let thermal: String = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        parts.append("thermal \(thermal)")
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            parts.append("low power mode")
        }

        #if os(iOS)
        parts.append(batteryDescription())
        #endif

        return parts.joined(separator: " | ")
    }

    #if os(iOS)
    /// Battery level, and the drain rate while unplugged once it is measurable.
    @MainActor
    private func batteryDescription() -> String {
        let device = UIDevice.current
        guard device.batteryLevel >= 0 else { return "battery ?" }
        let level = device.batteryLevel
        var text = "battery \(Int(level * 100))%"

        guard device.batteryState == .unplugged else {
            batteryReference = nil
            return text + " (\(device.batteryState == .full ? "full" : "charging"))"
        }
        guard let reference = batteryReference, level <= reference.level else {
            batteryReference = (Date(), level)
            return text
        }
        let hours = Date().timeIntervalSince(reference.date) / 3600
        if hours >= 5.0 / 60, reference.level > level {
            text += String(format: " (%.0f%%/h over %.0fm)", Double(reference.level - level) * 100 / hours, hours * 60)
        }
        return text
    }
    #endif
}

// MARK: - Period

/// Totals for one foreground or background period.
private struct Period {
    let background: Bool
    var wall: TimeInterval = 0
    var cpuSeconds: Double = 0
    var maxCPU: Double = 0
    var areaSeconds: [String: Double] = [:]
    var wakeups: Double = 0
    var counts: [String: Int] = [:]

    init(background: Bool) {
        self.background = background
    }

    mutating func add(_ sample: ResourceSample, counts: [String: Int]) {
        wall += sample.wall
        cpuSeconds += sample.cpuPercent / 100 * sample.wall
        if sample.wall >= 1 {
            maxCPU = max(maxCPU, sample.cpuPercent)
        }
        for area in sample.areas {
            areaSeconds[area.area, default: 0] += area.percent / 100 * sample.wall
        }
        wakeups += ((sample.idleWakeupsPerSecond ?? 0) + (sample.interruptWakeupsPerSecond ?? 0)) * sample.wall
        self.counts.merge(counts, uniquingKeysWith: +)
    }
}

// MARK: - MetricKit

#if os(iOS) || os(macOS)
/// Logs MetricKit payloads. The system delivers them at most daily (metrics)
/// or shortly after the event (diagnostics), usually on a later launch.
private final class MetricSubscriber: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            LoggingService.shared.log(level: .info, category: .performance,
                message: "MetricKit metrics \(payload.timeStampBegin.formatted()) – \(payload.timeStampEnd.formatted())",
                details: String(decoding: payload.jsonRepresentation(), as: UTF8.self))
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            var kinds: [String] = []
            if let cpu = payload.cpuExceptionDiagnostics, !cpu.isEmpty { kinds.append("\(cpu.count) CPU exception(s)") }
            if let hangs = payload.hangDiagnostics, !hangs.isEmpty { kinds.append("\(hangs.count) hang(s)") }
            if let disk = payload.diskWriteExceptionDiagnostics, !disk.isEmpty { kinds.append("\(disk.count) disk write exception(s)") }
            if let crashes = payload.crashDiagnostics, !crashes.isEmpty { kinds.append("\(crashes.count) crash(es)") }
            LoggingService.shared.log(level: kinds.isEmpty ? .info : .warning, category: .performance,
                message: "MetricKit diagnostics: \(kinds.isEmpty ? "none" : kinds.joined(separator: ", "))",
                details: String(decoding: payload.jsonRepresentation(), as: UTF8.self))
        }
    }
}
#endif
