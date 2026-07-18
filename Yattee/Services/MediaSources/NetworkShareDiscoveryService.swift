//
//  NetworkShareDiscoveryService.swift
//  Yattee
//
//  Discovers WebDAV and SMB shares on the local network using Bonjour/mDNS.
//

import Foundation
import Network

/// A network share discovered via Bonjour/mDNS.
struct DiscoveredShare: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String          // Service name (e.g., "Synology")
    let host: String          // Hostname (e.g., "synology.local")
    let port: Int?            // Port if non-standard
    let path: String?         // WebDAV path from TXT record
    let type: ShareType

    enum ShareType: String, CaseIterable, Sendable {
        case webdav    // _webdav._tcp (HTTP)
        case webdavs   // _webdavs._tcp (HTTPS)
        case smb       // _smb._tcp

        var displayName: String {
            switch self {
            case .webdav: String(localized: "discovery.shareType.webdav")
            case .webdavs: String(localized: "discovery.shareType.webdavs")
            case .smb: String(localized: "discovery.shareType.smb")
            }
        }

        var systemImage: String {
            switch self {
            case .webdav: "globe"
            case .webdavs: "lock.shield"
            case .smb: "folder.badge.gearshape"
            }
        }

        var serviceType: String {
            switch self {
            case .webdav: "_webdav._tcp"
            case .webdavs: "_webdavs._tcp"
            case .smb: "_smb._tcp"
            }
        }
    }

    /// Constructs a URL for this share.
    var url: URL? {
        var components = URLComponents()

        switch type {
        case .webdav:
            components.scheme = "http"
        case .webdavs:
            components.scheme = "https"
        case .smb:
            components.scheme = "smb"
        }

        components.host = host

        if let port, port != defaultPort {
            components.port = port
        }

        if let path, !path.isEmpty {
            components.path = path.hasPrefix("/") ? path : "/\(path)"
        }

        return components.url
    }

    private var defaultPort: Int {
        switch type {
        case .webdav: 80
        case .webdavs: 443
        case .smb: 445
        }
    }
}

/// Service for discovering WebDAV and SMB shares on the local network.
@MainActor
@Observable
final class NetworkShareDiscoveryService {

    // MARK: - Public State

    /// Discovered shares on the local network.
    private(set) var discoveredShares: [DiscoveredShare] = []

    /// Whether the service is actively scanning.
    private(set) var isScanning: Bool = false

    // MARK: - Private State

    private var browsers: [NWBrowser] = []
    private var discoveryTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "stream.yattee.networksharediscovery")

    /// Duration to scan before automatically stopping (in seconds).
    private let scanDuration: TimeInterval = 5.0

    // MARK: - Discovery

    /// Start discovering network shares. Automatically stops after 5 seconds.
    func startDiscovery() {
        guard !isScanning else {
            LoggingService.shared.logMediaSourcesDebug("Already scanning, ignoring duplicate start")
            return
        }

        LoggingService.shared.logMediaSources("Starting network share discovery")

        // Clear previous results
        discoveredShares = []
        isScanning = true

        // Start browsers for each service type
        for shareType in DiscoveredShare.ShareType.allCases {
            startBrowser(for: shareType)
        }

        // Auto-stop after scan duration
        discoveryTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(scanDuration))
            if isScanning {
                LoggingService.shared.logMediaSources("Scan timeout reached, stopping discovery")
                stopDiscovery()
            }
        }
    }

    /// Stop discovering network shares.
    func stopDiscovery() {
        guard isScanning else { return }

        LoggingService.shared.logMediaSources("Stopping network share discovery, found \(self.discoveredShares.count) shares")

        discoveryTask?.cancel()
        discoveryTask = nil

        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()

        isScanning = false
    }

    // MARK: - Private Methods

    private func startBrowser(for shareType: DiscoveredShare.ShareType) {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: shareType.serviceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserStateChange(state, shareType: shareType)
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            Task { @MainActor [weak self] in
                self?.handleBrowseResultsChanged(results: results, changes: changes, shareType: shareType)
            }
        }

        browser.start(queue: queue)
        browsers.append(browser)

        LoggingService.shared.logMediaSourcesDebug("Started browser for \(shareType.serviceType)")
    }

    private func handleBrowserStateChange(_ state: NWBrowser.State, shareType: DiscoveredShare.ShareType) {
        switch state {
        case .ready:
            LoggingService.shared.logMediaSourcesDebug("Browser ready for \(shareType.serviceType)")
        case .failed(let error):
            LoggingService.shared.logMediaSourcesError("Browser failed for \(shareType.serviceType)", error: error)
        case .cancelled:
            LoggingService.shared.logMediaSourcesDebug("Browser cancelled for \(shareType.serviceType)")
        case .waiting(let error):
            LoggingService.shared.logMediaSourcesWarning("Browser waiting for \(shareType.serviceType)", details: error.localizedDescription)
        default:
            break
        }
    }

    private func handleBrowseResultsChanged(
        results: Set<NWBrowser.Result>,
        changes: Set<NWBrowser.Result.Change>,
        shareType: DiscoveredShare.ShareType
    ) {
        for change in changes {
            switch change {
            case .added(let result):
                if let share = parseShare(from: result, shareType: shareType) {
                    // Avoid duplicates
                    if !discoveredShares.contains(where: { $0.host == share.host && $0.type == share.type && $0.name == share.name }) {
                        discoveredShares.append(share)
                        LoggingService.shared.logMediaSources("Discovered \(shareType.rawValue) share: \(share.name) at \(share.host)")
                    }
                }

            case .removed(let result):
                if case let .service(name, _, _, _) = result.endpoint {
                    discoveredShares.removeAll { $0.name == name && $0.type == shareType }
                    LoggingService.shared.logMediaSourcesDebug("Removed \(shareType.rawValue) share: \(name)")
                }

            case .changed, .identical:
                break

            @unknown default:
                break
            }
        }
    }

    private func parseShare(from result: NWBrowser.Result, shareType: DiscoveredShare.ShareType) -> DiscoveredShare? {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return nil
        }

        // Extract host from endpoint - use the service name with .local suffix
        let host = "\(name).local"

        // Parse TXT record for additional info
        var path: String?
        var port: Int?

        if case let .bonjour(txtRecord) = result.metadata {
            let dict = txtRecord.dictionary

            // WebDAV servers often advertise the path in TXT record
            if let txtPath = dict["path"] {
                path = txtPath
            }

            // Some servers advertise port in TXT record
            if let txtPort = dict["port"], let portNum = Int(txtPort) {
                port = portNum
            }
        }

        return DiscoveredShare(
            name: name,
            host: host,
            port: port,
            path: path,
            type: shareType
        )
    }
}
