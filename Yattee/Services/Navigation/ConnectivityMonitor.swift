//
//  ConnectivityMonitor.swift
//  Yattee
//
//  Network connectivity monitoring for offline mode support.
//

import Foundation
import Network

/// Monitors network connectivity status.
@Observable
final class ConnectivityMonitor: @unchecked Sendable {
    /// Whether the device is currently online.
    private(set) var isOnline: Bool = true

    /// Whether we're on a cellular connection.
    private(set) var isCellular: Bool = false

    /// Whether the connection is considered expensive (cellular or hotspot).
    private(set) var isExpensive: Bool = false

    /// Whether the connection is constrained (low data mode).
    private(set) var isConstrained: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "stream.yattee.connectivity")

    // MARK: - Lifecycle

    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    /// Start monitoring network connectivity.
    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOnline = path.status == .satisfied
                self?.isCellular = path.usesInterfaceType(.cellular)
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }

    /// Stop monitoring network connectivity.
    func stopMonitoring() {
        monitor.cancel()
    }
}
