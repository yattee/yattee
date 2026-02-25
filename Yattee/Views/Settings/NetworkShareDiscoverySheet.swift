//
//  NetworkShareDiscoverySheet.swift
//  Yattee
//
//  Sheet for discovering and selecting network shares (WebDAV/SMB) via Bonjour.
//

import SwiftUI

struct NetworkShareDiscoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    /// Called when user selects a share.
    let onSelect: (DiscoveredShare) -> Void

    /// Optional filter to show only specific share types.
    let filterType: DiscoveredShare.ShareType?

    init(filterType: DiscoveredShare.ShareType? = nil, onSelect: @escaping (DiscoveredShare) -> Void) {
        self.filterType = filterType
        self.onSelect = onSelect
    }

    private var discoveryService: NetworkShareDiscoveryService? {
        appEnvironment?.networkShareDiscoveryService
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "discovery.title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) {
                            discoveryService?.stopDiscovery()
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    discoveryService?.startDiscovery()
                }
                .onDisappear {
                    discoveryService?.stopDiscovery()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let service = discoveryService {
            List {
                // Scanning indicator
                if service.isScanning {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "discovery.scanning"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Filtered shares based on filterType
                let shares = filteredShares(from: service.discoveredShares)

                if shares.isEmpty && !service.isScanning {
                    // Empty state
                    Section {
                        ContentUnavailableView {
                            Label(String(localized: "discovery.empty.title"), systemImage: "network.slash")
                        } description: {
                            Text(String(localized: "discovery.empty.description"))
                        } actions: {
                            Button(String(localized: "discovery.scanAgain")) {
                                service.startDiscovery()
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // Group shares by type
                    let groupedShares = Dictionary(grouping: shares) { $0.type }

                    // WebDAV shares (combined webdav and webdavs)
                    let webdavShares = (groupedShares[.webdav] ?? []) + (groupedShares[.webdavs] ?? [])
                    if !webdavShares.isEmpty {
                        Section {
                            ForEach(webdavShares) { share in
                                ShareRow(share: share) {
                                    selectShare(share)
                                }
                            }
                        } header: {
                            Text(String(localized: "discovery.section.webdav"))
                        }
                    }

                    // SMB shares
                    if let smbShares = groupedShares[.smb], !smbShares.isEmpty {
                        Section {
                            ForEach(smbShares) { share in
                                ShareRow(share: share) {
                                    selectShare(share)
                                }
                            }
                        } header: {
                            Text(String(localized: "discovery.section.smb"))
                        }
                    }
                }
            }
            #if os(tvOS)
            .listStyle(.grouped)
            #endif
        } else {
            // No environment available
            ContentUnavailableView {
                Label(String(localized: "discovery.unavailable.title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(String(localized: "discovery.unavailable.description"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func filteredShares(from shares: [DiscoveredShare]) -> [DiscoveredShare] {
        guard let filterType else { return shares }

        switch filterType {
        case .webdav, .webdavs:
            // When filtering for WebDAV, include both HTTP and HTTPS variants
            return shares.filter { $0.type == .webdav || $0.type == .webdavs }
        case .smb:
            return shares.filter { $0.type == .smb }
        }
    }

    private func selectShare(_ share: DiscoveredShare) {
        discoveryService?.stopDiscovery()
        onSelect(share)
        dismiss()
    }
}

// MARK: - Share Row

private struct ShareRow: View {
    let share: DiscoveredShare
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: share.type.systemImage)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(share.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(addressDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if share.type == .webdavs {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        switch share.type {
        case .webdav: .blue
        case .webdavs: .green
        case .smb: .orange
        }
    }

    private var addressDisplay: String {
        var display = share.host

        if let port = share.port {
            display += ":\(port)"
        }

        if let path = share.path, !path.isEmpty {
            display += path.hasPrefix("/") ? path : "/\(path)"
        }

        return display
    }
}

// MARK: - Preview

#Preview {
    NetworkShareDiscoverySheet { _ in }
    .appEnvironment(.preview)
}
