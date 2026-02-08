//
//  DeviceCapabilitiesView.swift
//  Yattee
//
//  Shows device hardware capabilities and current network status.
//

import SwiftUI

struct DeviceCapabilitiesView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        List {
            hardwareDecodingSection
            networkStatusSection
            effectiveSettingsSection
        }
        .navigationTitle(String(localized: "settings.deviceCapabilities.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Hardware Decoding Section

    @ViewBuilder
    private var hardwareDecodingSection: some View {
        Section {
            ForEach(HardwareCapabilities.shared.allCapabilities, id: \.name) { capability in
                HStack {
                    Text(capability.name)
                    Spacer()
                    if capability.supported {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(String(localized: "settings.deviceCapabilities.hardwareDecoding"))
        } footer: {
            Text(String(localized: "settings.deviceCapabilities.hardwareDecoding.footer"))
        }
    }

    // MARK: - Network Status Section

    @ViewBuilder
    private var networkStatusSection: some View {
        if let connectivity = appEnvironment?.connectivityMonitor {
            Section {
                LabeledContent(String(localized: "settings.deviceCapabilities.network.connection")) {
                    Text(connectionTypeString(connectivity))
                }

                HStack {
                    Text(String(localized: "settings.deviceCapabilities.network.online"))
                    Spacer()
                    statusIndicator(connectivity.isOnline)
                }

                HStack {
                    Text(String(localized: "settings.deviceCapabilities.network.expensive"))
                    Spacer()
                    statusIndicator(connectivity.isExpensive)
                }

                HStack {
                    Text(String(localized: "settings.deviceCapabilities.network.lowDataMode"))
                    Spacer()
                    statusIndicator(connectivity.isConstrained)
                }
            } header: {
                Text(String(localized: "settings.deviceCapabilities.networkStatus"))
            } footer: {
                Text(String(localized: "settings.deviceCapabilities.networkStatus.footer"))
            }
        }
    }

    // MARK: - Effective Settings Section

    @ViewBuilder
    private var effectiveSettingsSection: some View {
        if let settings = appEnvironment?.settingsManager,
           let connectivity = appEnvironment?.connectivityMonitor {
            Section {
                LabeledContent(String(localized: "settings.deviceCapabilities.effective.qualityLimit")) {
                    Text(effectiveQualityString(settings: settings, connectivity: connectivity))
                }

                LabeledContent(String(localized: "settings.deviceCapabilities.effective.preferredCodecs")) {
                    Text(HardwareCapabilities.shared.preferredCodecOrder.joined(separator: ", "))
                }
            } header: {
                Text(String(localized: "settings.deviceCapabilities.effectiveSettings"))
            } footer: {
                Text(String(localized: "settings.deviceCapabilities.effectiveSettings.footer"))
            }
        }
    }

    // MARK: - Helpers

    private func connectionTypeString(_ connectivity: ConnectivityMonitor) -> String {
        if connectivity.isCellular {
            return String(localized: "settings.deviceCapabilities.network.type.cellular")
        } else if connectivity.isOnline {
            return String(localized: "settings.deviceCapabilities.network.type.wifi")
        } else {
            return String(localized: "settings.deviceCapabilities.network.type.offline")
        }
    }

    @ViewBuilder
    private func statusIndicator(_ isActive: Bool) -> some View {
        if isActive {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func effectiveQualityString(settings: SettingsManager, connectivity: ConnectivityMonitor) -> String {
        let quality: VideoQuality
        if connectivity.isConstrained {
            quality = .sd480p
        } else if connectivity.isCellular || connectivity.isExpensive {
            quality = settings.cellularQuality
        } else {
            quality = settings.preferredQuality
        }

        if quality == .auto {
            return String(localized: "settings.deviceCapabilities.effective.auto")
        }
        return quality.rawValue.uppercased()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DeviceCapabilitiesView()
    }
}
