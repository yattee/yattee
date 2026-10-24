//
//  BackgroundDiagnostics.swift
//  Yattee
//
//  Heartbeat and event logging to diagnose battery drain and heat while the
//  app is in the background.
//

import Foundation

/// Render activity counters, reset each time they are read.
final class RenderDiagnosticsCounters: @unchecked Sendable {
    struct Counts {
        var linkFires = 0
        var renders = 0
        var presents = 0
        var backgroundRenders = 0
        var skippedInBackground = 0
    }

    private let lock = NSLock()
    private var counts = Counts()

    func increment(_ key: WritableKeyPath<Counts, Int>) {
        lock.withLock { counts[keyPath: key] += 1 }
    }

    func take() -> Counts {
        lock.withLock {
            defer { counts = Counts() }
            return counts
        }
    }
}

#if os(iOS)
import AVFoundation
import UIKit

/// Logs a process/app/player snapshot every 10 seconds while the app is not
/// active (every 30 seconds while active), plus lifecycle, audio and power
/// events, under the Diagnostics category.
///
/// Only does work while "Enable Logging" is on. Logs are persisted to disk by
/// `LogFileStore`, so they survive the app being swiped away.
///
/// The heartbeat timer runs on its own queue, independent of the main thread:
/// a "heartbeat gap" means the whole process was suspended, while a heartbeat
/// without its app snapshot means the main thread was blocked.
@MainActor
final class BackgroundDiagnostics {
    static let shared = BackgroundDiagnostics()

    private weak var playerService: PlayerService?
    private var observers: [NSObjectProtocol] = []
    private var runLoopObserver: CFRunLoopObserver?
    private var runLoopWakeups = 0
    private var started = false
    private let sampler = ProcessSampler()

    private init() {}

    func start(playerService: PlayerService) {
        guard !started else { return }
        started = true
        self.playerService = playerService

        UIDevice.current.isBatteryMonitoringEnabled = true
        sampler.setMainThreadPort(pthread_mach_thread_np(pthread_self()))
        installRunLoopObserver()
        observeEvents()
        sampler.start()
        log(.info, "Diagnostics started", details: appSnapshot())
    }

    // MARK: - Snapshot

    /// App, device, player, audio and render state. Must run on the main thread.
    func appSnapshot() -> String {
        let app = UIApplication.shared
        var lines: [String] = []

        var appLine = "app: state=\(describe(app.applicationState))"
        if app.applicationState == .background {
            let remaining = app.backgroundTimeRemaining
            appLine += " bgTimeRemaining=" + (remaining > 1e6 ? "unlimited" : "\(Int(remaining))s")
        }
        appLine += " protectedData=\(app.isProtectedDataAvailable ? "available" : "locked")"
        appLine += " scenes=[\(app.connectedScenes.map { describe($0.activationState) }.joined(separator: ","))]"
        appLine += " idleTimerDisabled=\(app.isIdleTimerDisabled)"
        lines.append(appLine)

        let device = UIDevice.current
        let battery = device.batteryLevel < 0 ? "?" : "\(Int(device.batteryLevel * 100))%"
        lines.append("device: thermal=\(describe(ProcessInfo.processInfo.thermalState)) battery=\(battery)"
            + " batteryState=\(describe(device.batteryState)) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")

        lines.append("mainRunLoop: wakeups=\(runLoopWakeups) since last sample")
        runLoopWakeups = 0

        if let playerService {
            let state = playerService.state
            lines.append("player: state=\(describe(state.playbackState)) pip=\(state.pipState)"
                + " backend=\(playerService.currentBackendType) video=\(state.currentVideo?.id.videoID ?? "none")"
                + " time=\(Int(state.currentTime))/\(Int(state.duration))"
                + " publishesTime=\(state.publishesTimeUpdates)")
        }

        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue)(\($0.portName))" }
        lines.append("audio: category=\(session.category.rawValue) mode=\(session.mode.rawValue)"
            + " otherAudioPlaying=\(session.isOtherAudioPlaying)"
            + " silenceSecondaryHint=\(session.secondaryAudioShouldBeSilencedHint)"
            + " route=[\(outputs.joined(separator: ","))]")

        let renderViews = MPVRenderView.diagnosticsInstances
        if renderViews.isEmpty {
            lines.append("render: no MPV render views")
        } else {
            lines.append(contentsOf: renderViews.map { "render: " + $0.diagnosticsSummary() })
        }

        return lines.joined(separator: "\n")
    }

    /// Called by the sampler with the process-level part of a heartbeat.
    nonisolated fileprivate func deliverHeartbeat(process: String, highCPU: Bool, enqueuedAt: DispatchTime) {
        let latencyMs = (DispatchTime.now().uptimeNanoseconds - enqueuedAt.uptimeNanoseconds) / 1_000_000
        MainActor.assumeIsolated {
            let state = describe(UIApplication.shared.applicationState)
            // Background playback legitimately costs CPU; flag only when nothing is playing.
            let isPlaying = playerService?.state.playbackState == .playing
            log(highCPU && !isPlaying ? .warning : .info, "Heartbeat [\(state)]",
                details: process + "\nmainThread: latency=\(latencyMs)ms\n" + appSnapshot())
        }
    }

    // MARK: - Events

    private func installRunLoopObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, 0) { _, _ in
            MainActor.assumeIsolated {
                BackgroundDiagnostics.shared.runLoopWakeups += 1
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        runLoopObserver = observer
    }

    private func observeEvents() {
        let center = NotificationCenter.default

        let lifecycle: [(Notification.Name, String)] = [
            (UIApplication.willResignActiveNotification, "App will resign active"),
            (UIApplication.didEnterBackgroundNotification, "App did enter background"),
            (UIApplication.willEnterForegroundNotification, "App will enter foreground"),
            (UIApplication.didBecomeActiveNotification, "App did become active"),
            (UIApplication.willTerminateNotification, "App will terminate"),
            (UIApplication.didReceiveMemoryWarningNotification, "Memory warning"),
            (UIApplication.protectedDataWillBecomeUnavailableNotification, "Device locking (protected data unavailable)"),
            (UIApplication.protectedDataDidBecomeAvailableNotification, "Device unlocked (protected data available)"),
            (ProcessInfo.thermalStateDidChangeNotification, "Thermal state changed"),
            (Notification.Name.NSProcessInfoPowerStateDidChange, "Low Power Mode changed"),
            (UIDevice.batteryStateDidChangeNotification, "Battery state changed"),
            (UIDevice.batteryLevelDidChangeNotification, "Battery level changed"),
            (AVAudioSession.mediaServicesWereResetNotification, "Audio media services were reset"),
            (AVAudioSession.mediaServicesWereLostNotification, "Audio media services were lost"),
        ]
        for (name, message) in lifecycle {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    BackgroundDiagnostics.shared.logEvent(message)
                }
            })
        }

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { notification in
            let info = notification.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let reason = (info[AVAudioSessionInterruptionReasonKey] as? UInt).flatMap(AVAudioSession.InterruptionReason.init)
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            let details = "type=\(type == .began ? "began" : type == .ended ? "ended" : "?")"
                + " reason=\(reason.map { "\($0.rawValue)" } ?? "none")"
                + " shouldResume=\(options?.contains(.shouldResume) ?? false)"
            MainActor.assumeIsolated {
                BackgroundDiagnostics.shared.logEvent("Audio interruption", extra: details)
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { notification in
            let info = notification.userInfo ?? [:]
            let reason = (info[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
            let previous = (info[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)?
                .outputs.map { $0.portType.rawValue }.joined(separator: ",") ?? "?"
            let details = "reason=\(reason.map { "\($0.rawValue)" } ?? "?") previousRoute=[\(previous)]"
            MainActor.assumeIsolated {
                BackgroundDiagnostics.shared.logEvent("Audio route changed", extra: details)
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: .main) { notification in
            let type = (notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt)
                .flatMap(AVAudioSession.SilenceSecondaryAudioHintType.init)
            let details = "type=\(type == .begin ? "begin" : type == .end ? "end" : "?")"
            MainActor.assumeIsolated {
                BackgroundDiagnostics.shared.logEvent("Silence secondary audio hint", extra: details)
            }
        })
    }

    private func logEvent(_ message: String, extra: String? = nil) {
        guard LoggingService.shared.isEnabled else { return }
        var details = appSnapshot()
        if let extra {
            details = extra + "\n" + details
        }
        log(.info, message, details: details)
        // A fresh process sample right at the transition, and the cadence follows the new state.
        sampler.setAppActive(UIApplication.shared.applicationState == .active)
        sampler.sampleSoon()
    }

    private func log(_ level: LogLevel, _ message: String, details: String) {
        LoggingService.shared.log(level: level, category: .diagnostics, message: message, details: details)
    }

    // MARK: - Descriptions

    private func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown(\(state.rawValue))"
        }
    }

    private func describe(_ state: UIScene.ActivationState) -> String {
        switch state {
        case .foregroundActive: "foregroundActive"
        case .foregroundInactive: "foregroundInactive"
        case .background: "background"
        case .unattached: "unattached"
        @unknown default: "unknown"
        }
    }

    private func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private func describe(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: "unknown"
        case .unplugged: "unplugged"
        case .charging: "charging"
        case .full: "full"
        @unknown default: "unknown"
        }
    }

    private func describe(_ state: PlaybackState) -> String {
        if case .failed = state { return "failed" }
        return "\(state)"
    }
}

/// Samples process CPU, per-thread CPU, wakeups, GPU time and memory on its own
/// queue. All mutable state is confined to `queue`.
private final class ProcessSampler: @unchecked Sendable {
    private static let interval: TimeInterval = 10
    /// While the app is active, log only every Nth sample.
    private static let activeLogEvery = 3
    /// Process CPU above this while not active is logged as a warning.
    private static let highCPUPercent = 15.0

    private let queue = DispatchQueue(label: "stream.yattee.diagnostics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isAppActive = true
    private var tick = 0

    private var lastTick: Date?
    private var resourceSampler: ResourceSampler?
    private var pendingSoon = false

    func setMainThreadPort(_ port: mach_port_t) {
        queue.async { self.resourceSampler = ResourceSampler(mainThreadPort: port) }
    }

    func setAppActive(_ active: Bool) {
        queue.async { self.isAppActive = active }
    }

    func start() {
        queue.async {
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .seconds(1))
            timer.setEventHandler { self.fire(forced: false) }
            timer.resume()
            self.timer = timer
            _ = self.sample()  // baseline
        }
    }

    /// Take an extra sample shortly after a lifecycle event.
    func sampleSoon() {
        queue.async {
            guard !self.pendingSoon else { return }
            self.pendingSoon = true
            self.queue.asyncAfter(deadline: .now() + 1) {
                self.pendingSoon = false
                self.fire(forced: true)
            }
        }
    }

    private func fire(forced: Bool) {
        guard UserDefaults.standard.bool(forKey: "loggingEnabled") else {
            lastTick = nil
            return
        }

        let now = Date()
        if !forced, let lastTick {
            let gap = now.timeIntervalSince(lastTick)
            if gap > Self.interval * 2.5 {
                LoggingService.shared.log(level: .warning, category: .diagnostics,
                    message: "Heartbeat gap: \(Int(gap))s since previous heartbeat",
                    details: "The process was suspended (or not scheduled) during the gap.")
            }
        }
        if !forced {
            lastTick = now
            tick += 1
        }

        let process = sample()
        guard forced || !isAppActive || tick % Self.activeLogEvery == 0 else { return }

        let highCPU = !isAppActive && process.cpuPercent >= Self.highCPUPercent
        let enqueuedAt = DispatchTime.now()
        let responded = ResponseFlag()
        DispatchQueue.main.async {
            responded.set()
            BackgroundDiagnostics.shared.deliverHeartbeat(process: process.text, highCPU: highCPU, enqueuedAt: enqueuedAt)
        }
        queue.asyncAfter(deadline: .now() + 3) {
            guard !responded.isSet else { return }
            LoggingService.shared.log(level: .warning, category: .diagnostics,
                message: "Heartbeat: main thread did not respond within 3s", details: process.text)
        }
    }

    // MARK: - Sampling

    private struct ProcessSample {
        let text: String
        let cpuPercent: Double
    }

    private func sample() -> ProcessSample {
        guard let resourceSampler else { return ProcessSample(text: "cpu: unavailable", cpuPercent: 0) }
        let sample = resourceSampler.sample()
        let footprint = sample.footprintMB.map { "\($0)MB" } ?? "?"
        let text = String(format: "cpu: process=%.1f%% over %.0fs", sample.cpuPercent, sample.wall)
            + " threads=\(sample.threadCount) footprint=\(footprint)\n"
            + "hotThreads: \(sample.hotThreadsText)\n"
            + sample.powerText
        return ProcessSample(text: text, cpuPercent: sample.cpuPercent)
    }
}

/// Set from the main thread, read on the sampler queue.
private final class ResponseFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() {
        lock.withLock { value = true }
    }
}
#endif
