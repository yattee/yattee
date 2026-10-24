//
//  PerformanceCounters.swift
//  Yattee
//
//  Activity counters for performance logging. Each counter is reported as a
//  rate by PerformanceMonitor, so a log shows what the app was busy doing.
//

import Foundation
import Synchronization

/// Named activity counters, safe to bump from any thread.
///
/// Counting is a no-op unless Performance Logging is on, so call sites can
/// stay in hot paths:
///
///     PerfCounter.count("mpv.prop.time-pos")
///
/// In a SwiftUI body, count evaluations with `let _ = PerfCounter.body("Name")`.
enum PerfCounter {
    private static let isEnabled = Atomic<Bool>(false)

    private static let counts = Mutex<[String: Int]>([:])

    @inline(__always)
    static var enabled: Bool { isEnabled.load(ordering: .relaxed) }

    static func setEnabled(_ enabled: Bool) {
        isEnabled.store(enabled, ordering: .relaxed)
    }

    static func count(_ key: String, by amount: Int = 1) {
        guard enabled else { return }
        counts.withLock { $0[key, default: 0] += amount }
    }

    /// Counts one body evaluation of the named view.
    static func body(_ name: StaticString) {
        guard enabled else { return }
        let key = "view." + name.description
        counts.withLock { $0[key, default: 0] += 1 }
    }

    /// Returns the counts accumulated since the last call and resets them.
    static func take() -> [String: Int] {
        counts.withLock {
            defer { $0 = [:] }
            return $0
        }
    }
}
