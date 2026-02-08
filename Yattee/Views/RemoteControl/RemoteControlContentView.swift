//
//  RemoteControlContentView.swift
//  Yattee
//
//  Shared content view for remote control settings used by both
//  Settings and the toolbar sheet.
//

import SwiftUI

/// Navigation style for device rows - determines how navigation is handled.
enum RemoteControlNavigationStyle {
    /// Use NavigationLink for navigation (Settings context)
    case link
    /// Use Button with external selection binding (Sheet context)
    case selection(Binding<DiscoveredDevice?>)
}

/// Shared content view containing all remote control sections.
/// Used by both RemoteControlSettingsView and RemoteDevicesSheet.
struct RemoteControlContentView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.sheetContentHeight) private var sheetContentHeight

    let navigationStyle: RemoteControlNavigationStyle

    /// Timer to refresh the view for live time updates and device cleanup.
    @State private var refreshTimer: Timer?
    /// Incremented to trigger SwiftUI re-render (deviceStatus is computed, not observed).
    @State private var refreshTick: Int = 0

    private var remoteControl: RemoteControlCoordinator? {
        appEnvironment?.remoteControlCoordinator
    }

    private var networkService: LocalNetworkService? {
        appEnvironment?.localNetworkService
    }

    /// Calculate content height based on visible elements.
    private var calculatedHeight: CGFloat {
        var height: CGFloat = 100 // Base: nav bar + padding

        // Devices section
        let deviceCount = remoteControl?.discoveredDevices.count ?? 0
        let rowCount = max(deviceCount, 1) // At least 1 for placeholder
        height += CGFloat(rowCount) * 70 + 50 // Rows + section header

        // Enable section
        height += 60 // Toggle row
        if remoteControl?.isEnabled == true {
            height += 45 // Status row
        }
        height += 70 // Footer text

        return height
    }

    var body: some View {
        List {
            discoveredDevicesSection
            enableSection
        }
        .onAppear {
            startRefreshTimer()
            sheetContentHeight?.wrappedValue = calculatedHeight
        }
        .onChange(of: remoteControl?.discoveredDevices.count) { _, _ in
            sheetContentHeight?.wrappedValue = calculatedHeight
        }
        .onChange(of: remoteControl?.isEnabled) { _, _ in
            sheetContentHeight?.wrappedValue = calculatedHeight
        }
        .onDisappear {
            stopRefreshTimer()
        }
    }

    // MARK: - Refresh Timer

    private func startRefreshTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            Task { @MainActor in
                refreshTick += 1
                // Also trigger cleanup of stale devices
                networkService?.cleanupStaleDevices()
            }
        }
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Enable Section

    private var isIncognito: Bool {
        appEnvironment?.settingsManager.incognitoModeEnabled ?? false
    }

    @ViewBuilder
    private var enableSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { remoteControl?.isEnabled ?? false },
                set: { remoteControl?.isEnabled = $0 }
            )) {
                Label(String(localized: "remoteControl.enable"), systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(isIncognito)

            if remoteControl?.isEnabled == true && !isIncognito {
                statusRow
            }
        } footer: {
            if isIncognito {
                Text(String(localized: "remoteControl.enableFooter.incognito"))
            } else {
                Text(String(localized: "remoteControl.enableFooter"))
            }
        }
    }

    // MARK: - Status Row

    @ViewBuilder
    private var statusRow: some View {
        HStack {
            Text(String(localized: "remoteControl.status"))
            Spacer()
            if networkService?.isHosting == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(String(localized: "remoteControl.status.discoverable"))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(String(localized: "remoteControl.status.notDiscoverable"))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Discovered Devices Section

    @ViewBuilder
    private var discoveredDevicesSection: some View {
        Section {
            if remoteControl?.isEnabled != true {
                // Placeholder when disabled
                HStack {
                    Spacer()
                    Text(String(localized: "remoteControl.enableToDiscover"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let devices = remoteControl?.discoveredDevices, !devices.isEmpty {
                // refreshTick triggers re-render for live status updates
                let _ = refreshTick
                ForEach(devices) { device in
                    deviceRow(for: device)
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(String(localized: "remoteControl.searchingDevices"))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        } header: {
            HStack {
                Text(String(localized: "remoteControl.devicesOnNetwork"))
                Spacer()
                if remoteControl?.isEnabled == true, let count = remoteControl?.discoveredDevices.count, count > 0 {
                    Text(String(localized: "remoteControl.devicesFound \(count)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if remoteControl?.isEnabled == true, remoteControl?.discoveredDevices.isEmpty == true {
                Text(String(localized: "remoteControl.noDevicesFooter"))
            }
        }
    }

    @ViewBuilder
    private func deviceRow(for device: DiscoveredDevice) -> some View {
        let status = networkService?.deviceStatus(for: device.id) ?? .discoveredOnly

        switch navigationStyle {
        case .link:
            NavigationLink {
                RemoteControlView(device: device)
            } label: {
                DeviceRowContent(device: device, status: status)
            }

        case .selection(let binding):
            Button {
                binding.wrappedValue = device
            } label: {
                DeviceRowContent(device: device, status: status, showChevron: true)
            }
            #if !os(tvOS)
            .buttonStyle(.plain)
            #endif
        }
    }
}

// MARK: - Device Row Content

/// Shared device row content used in both navigation styles.
private struct DeviceRowContent: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let device: DiscoveredDevice
    let status: LocalNetworkService.DeviceStatus
    var showChevron: Bool = false

    private var remoteControl: RemoteControlCoordinator? {
        appEnvironment?.remoteControlCoordinator
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.platform.iconName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                // Title line: video info (or device name if no video)
                if let title = device.currentVideoTitle {
                    Text(videoSubtitle(title: title, channel: device.currentChannelName))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.body)
                            .foregroundStyle(.primary)

                        // Status indicator (next to device name when no video)
                        statusBadge
                    }
                }

                // Subtitle line: device name with status (or "no video" if no video)
                if device.currentVideoTitle != nil {
                    HStack(spacing: 6) {
                        Text(device.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Status indicator (next to device name)
                        statusBadge
                    }
                } else {
                    Text(String(localized: "remoteControl.noVideoPlaying"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            #if !os(tvOS)
            // Play/Pause button when video is loaded
            if device.currentVideoTitle != nil {
                Button {
                    Task {
                        await remoteControl?.togglePlayPause(on: device)
                    }
                } label: {
                    Image(systemName: device.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                }
                .buttonStyle(.borderless)
            }
            #endif

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .connected:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(.green)

        case .recentlySeen(let ago):
            HStack(spacing: 3) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                Text(formatSeenAgo(ago))
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.orange)

        case .discoveredOnly:
            EmptyView()
        }
    }

    private func formatSeenAgo(_ seconds: TimeInterval) -> String {
        let date = Date().addingTimeInterval(-seconds)
        return RelativeDateFormatter.string(for: date, justNowThreshold: 5)
    }

    private func videoSubtitle(title: String, channel: String?) -> String {
        if let channel, !channel.isEmpty {
            return "\(title) · \(channel)"
        }
        return title
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RemoteControlContentView(navigationStyle: .link)
            .navigationTitle(String(localized: "remoteControl.title"))
    }
    .appEnvironment(.preview)
}
