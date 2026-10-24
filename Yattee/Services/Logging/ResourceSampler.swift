//
//  ResourceSampler.swift
//  Yattee
//
//  Measures the process's CPU, per-thread CPU, wakeups, GPU, memory
//  and disk activity between two samples.
//

import Foundation

/// One measurement window, from the previous `sample()` call to this one.
struct ResourceSample {
    struct Thread {
        let name: String
        let area: String
        let percent: Double
    }

    let wall: TimeInterval
    /// Percent of one core, all threads.
    let cpuPercent: Double
    let userPercent: Double
    let systemPercent: Double
    let threadCount: Int
    /// Threads that used CPU in the window, busiest first.
    let threads: [Thread]
    let idleWakeupsPerSecond: Double?
    let interruptWakeupsPerSecond: Double?
    let gpuPercent: Double?
    let footprintMB: UInt64?
    let diskReadOps: Int
    let diskWriteOps: Int

    /// CPU percent grouped by area (ui, playback, audio, network, …), busiest first.
    /// CPU of threads that exited during the window is reported as "exited".
    var areas: [(area: String, percent: Double)] {
        var totals: [String: Double] = [:]
        for thread in threads {
            totals[thread.area, default: 0] += thread.percent
        }
        let unattributed = cpuPercent - threads.reduce(0) { $0 + $1.percent }
        if unattributed >= 0.5 {
            totals["exited", default: 0] += unattributed
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var hotThreadsText: String {
        let hot = threads.filter { $0.percent >= 0.5 }.prefix(8)
        guard !hot.isEmpty else { return "none" }
        return hot.map { String(format: "%@ %.1f%%", $0.name, $0.percent) }.joined(separator: ", ")
    }

    var areasText: String {
        let areas = areas.filter { $0.percent >= 0.1 }
        guard !areas.isEmpty else { return "idle" }
        return areas.map { String(format: "%@ %.1f", $0.area, $0.percent) }.joined(separator: " ")
    }

    var powerText: String {
        var parts: [String] = []
        if let idle = idleWakeupsPerSecond, let interrupts = interruptWakeupsPerSecond {
            parts.append(String(format: "wakeups %.0f/s (idle %.0f, interrupt %.0f)", idle + interrupts, idle, interrupts))
        }
        if let gpuPercent {
            parts.append(String(format: "gpu %.1f%%", gpuPercent))
        }
        return parts.isEmpty ? "power: unavailable" : parts.joined(separator: " | ")
    }
}

/// Keeps the previous sample's counters; not thread-safe, confine each
/// instance to one queue.
final class ResourceSampler {
    private var mainThreadPort: mach_port_t = 0
    private var lastSampleTime: DispatchTime?
    private var lastUserCPU: Double = 0
    private var lastSystemCPU: Double = 0
    private var lastThreadCPU: [UInt64: UInt64] = [:]
    private var lastIdleWakeups: UInt64 = 0
    private var lastInterruptWakeups: UInt64 = 0
    private var lastGPUNanoseconds: UInt64 = 0
    private var lastInBlocks: Int = 0
    private var lastOutBlocks: Int = 0

    /// Call from the main thread so the main thread can be named in samples.
    init(mainThreadPort: mach_port_t) {
        self.mainThreadPort = mainThreadPort
    }

    /// Resets the baseline without producing a meaningful sample.
    func reset() {
        _ = sample()
    }

    func sample() -> ResourceSample {
        let now = DispatchTime.now()
        let wall = lastSampleTime.map { Double(now.uptimeNanoseconds - $0.uptimeNanoseconds) / 1e9 } ?? 0
        lastSampleTime = now

        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = seconds(usage.ru_utime)
        let system = seconds(usage.ru_stime)
        let userPercent = wall > 0 ? (user - lastUserCPU) / wall * 100 : 0
        let systemPercent = wall > 0 ? (system - lastSystemCPU) / wall * 100 : 0
        lastUserCPU = user
        lastSystemCPU = system
        let diskReadOps = usage.ru_inblock - lastInBlocks
        let diskWriteOps = usage.ru_oublock - lastOutBlocks
        lastInBlocks = usage.ru_inblock
        lastOutBlocks = usage.ru_oublock

        let (threadCount, threads) = sampleThreads(wall: wall)

        var idleWakeups: Double?
        var interruptWakeups: Double?
        var gpuPercent: Double?
        var power = task_power_info_v2()
        var powerCount = mach_msg_type_number_t(MemoryLayout<task_power_info_v2>.size / MemoryLayout<natural_t>.size)
        let powerResult = withUnsafeMutablePointer(to: &power) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(powerCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO_V2), $0, &powerCount)
            }
        }
        if powerResult == KERN_SUCCESS {
            let idle = power.cpu_energy.task_platform_idle_wakeups
            let interrupts = power.cpu_energy.task_interrupt_wakeups
            let gpu = power.gpu_energy.task_gpu_utilisation
            if wall > 0 {
                idleWakeups = Double(idle &- lastIdleWakeups) / wall
                interruptWakeups = Double(interrupts &- lastInterruptWakeups) / wall
                gpuPercent = Double(gpu &- lastGPUNanoseconds) / 1e9 / wall * 100
            }
            lastIdleWakeups = idle
            lastInterruptWakeups = interrupts
            lastGPUNanoseconds = gpu
        }

        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }

        return ResourceSample(
            wall: wall,
            cpuPercent: userPercent + systemPercent,
            userPercent: userPercent,
            systemPercent: systemPercent,
            threadCount: threadCount,
            threads: threads,
            idleWakeupsPerSecond: idleWakeups,
            interruptWakeupsPerSecond: interruptWakeups,
            gpuPercent: gpuPercent,
            footprintMB: vmResult == KERN_SUCCESS ? vmInfo.phys_footprint / 1_048_576 : nil,
            diskReadOps: diskReadOps,
            diskWriteOps: diskWriteOps
        )
    }

    /// Per-thread CPU since the last sample.
    private func sampleThreads(wall: TimeInterval) -> (count: Int, threads: [ResourceSample.Thread]) {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS, let threadList else {
            return (0, [])
        }
        defer {
            for index in 0..<Int(threadCount) {
                mach_port_deallocate(mach_task_self_, threadList[index])
            }
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)),
                vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.stride))
        }

        var current: [UInt64: UInt64] = [:]
        var threads: [ResourceSample.Thread] = []
        for index in 0..<Int(threadCount) {
            let thread = threadList[index]

            var identifier = thread_identifier_info()
            var identifierCount = mach_msg_type_number_t(MemoryLayout<thread_identifier_info>.size / MemoryLayout<natural_t>.size)
            let identifierResult = withUnsafeMutablePointer(to: &identifier) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(identifierCount)) {
                    thread_info(thread, thread_flavor_t(THREAD_IDENTIFIER_INFO), $0, &identifierCount)
                }
            }

            var info = thread_extended_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_extended_info>.size / MemoryLayout<natural_t>.size)
            let infoResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(thread, thread_flavor_t(THREAD_EXTENDED_INFO), $0, &infoCount)
                }
            }
            guard identifierResult == KERN_SUCCESS, infoResult == KERN_SUCCESS else { continue }

            let id = identifier.thread_id
            let total = info.pth_user_time + info.pth_system_time  // nanoseconds
            current[id] = total
            guard wall > 0 else { continue }
            let percent = Double(total &- (lastThreadCPU[id] ?? total)) / 1e9 / wall * 100
            guard percent > 0 else { continue }

            var name = withUnsafeBytes(of: info.pth_name) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if thread == mainThreadPort {
                name = "main"
            } else if name.isEmpty {
                name = "unnamed"
            }
            threads.append(.init(name: name, area: Self.area(forThread: name), percent: percent))
        }
        lastThreadCPU = current

        // Merge same-named threads (e.g. several "unnamed" GCD workers).
        var merged: [String: ResourceSample.Thread] = [:]
        for thread in threads {
            let percent = (merged[thread.name]?.percent ?? 0) + thread.percent
            merged[thread.name] = .init(name: thread.name, area: thread.area, percent: percent)
        }
        return (Int(threadCount), merged.values.sorted { $0.percent > $1.percent })
    }

    /// What a thread is doing, from its name.
    static func area(forThread name: String) -> String {
        let lower = name.lowercased()
        if name == "main" { return "ui" }
        // mpv names its threads after their role ("core", "demux", "vo", …).
        if ["core", "demux", "vo", "ao", "cache", "dec"].contains(lower)
            || ["mpv", "stream.yattee.mpv", "lavf", "ffmpeg"].contains(where: lower.hasPrefix) {
            return "playback"
        }
        if lower.contains("auremoteio") || lower.contains("audio") || lower.contains("aqclient") {
            return "audio"
        }
        if lower.contains("nsurlconnection") || lower.contains("com.apple.network") || lower.contains("cfnetwork") {
            return "network"
        }
        if lower.contains("coremedia") || lower.contains("videotoolbox") || lower.contains("vtdecode") {
            return "media"
        }
        if lower.contains("cloudkit") {
            return "cloudkit"
        }
        if lower.hasPrefix("stream.yattee.diagnostics") || lower.hasPrefix("stream.yattee.logfile")
            || lower.hasPrefix("stream.yattee.performance") {
            return "logging"
        }
        return "other"
    }

    private func seconds(_ time: timeval) -> Double {
        Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000
    }
}
