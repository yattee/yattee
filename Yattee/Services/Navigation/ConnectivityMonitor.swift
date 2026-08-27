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
                let wasOffline = self?.isOnline == false
                self?.isOnline = path.status == .satisfied

                // Anything that gave up while there was no network needs to
                // hear that there is one again — an account marked unreachable
                // stops reads from going out at all, so nothing else would ever
                // discover it.
                if wasOffline, path.status == .satisfied {
                    NotificationCenter.default.post(name: .connectivityDidReturn, object: nil)
                }

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

extension Notification.Name {
    /// Posted when the device goes from offline to online.
    static let connectivityDidReturn = Notification.Name("stream.yattee.connectivityDidReturn")
}
