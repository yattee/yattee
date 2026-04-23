//
//  DownloadSettingsView.swift
//  Yattee
//
//  Settings view for download configuration.
//

import SwiftUI

#if !os(tvOS)
struct DownloadSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Form {
            if let downloadSettings = appEnvironment?.downloadSettings,
               let downloadManager = appEnvironment?.downloadManager {
                StorageSection(downloadManager: downloadManager)
                QualitySection(downloadSettings: downloadSettings)
                ConcurrencySection(downloadSettings: downloadSettings)
                #if os(iOS)
                CellularSection(
                    downloadSettings: downloadSettings,
                    downloadManager: downloadManager
                )
                #endif
            }
        }
        .navigationTitle(String(localized: "settings.downloads.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Storage Section

private struct StorageSection: View {
    let downloadManager: DownloadManager

    private var storageUsed: Int64 {
        downloadManager.storageUsed
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var body: some View {
        Section {
            NavigationLink {
                DownloadsStorageView()
            } label: {
                HStack {
                    Text(String(localized: "settings.downloads.usedStorage"))
                    Spacer()
                    Text(formatBytes(storageUsed))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Quality Section

private struct QualitySection: View {
    @Bindable var downloadSettings: DownloadSettings

    var body: some View {
        Section {
            Picker(
                String(localized: "settings.downloads.preferredQuality"),
                selection: $downloadSettings.preferredDownloadQuality
            ) {
                ForEach(DownloadQuality.allCases, id: \.self) { quality in
                    Text(quality.displayName).tag(quality)
                }
            }

            if downloadSettings.preferredDownloadQuality != .ask {
                Toggle(
                    String(localized: "settings.downloads.includeSubtitles"),
                    isOn: $downloadSettings.includeSubtitlesInAutoDownload
                )
            }
        } header: {
            Text(String(localized: "settings.downloads.quality.header"))
        } footer: {
            if downloadSettings.preferredDownloadQuality == .ask {
                Text(String(localized: "settings.downloads.quality.ask.footer"))
            } else {
                Text(String(localized: "settings.downloads.quality.auto.footer"))
            }
        }
    }
}

// MARK: - Concurrency Section

private struct ConcurrencySection: View {
    @Bindable var downloadSettings: DownloadSettings

    var body: some View {
        Section {
            #if os(iOS)
            Stepper(value: $downloadSettings.maxConcurrentDownloads, in: 1...5) {
                HStack {
                    Text(String(localized: "settings.downloads.maxConcurrent"))
                    Spacer()
                    Text("\(downloadSettings.maxConcurrentDownloads)")
                        .foregroundStyle(.secondary)
                }
            }
            #else
            Stepper(
                "\(String(localized: "settings.downloads.maxConcurrent")): \(downloadSettings.maxConcurrentDownloads)",
                value: $downloadSettings.maxConcurrentDownloads,
                in: 1...5
            )
            #endif
        }
    }
}

// MARK: - Cellular Section

#if os(iOS)
private struct CellularSection: View {
    @Bindable var downloadSettings: DownloadSettings
    let downloadManager: DownloadManager?

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.downloads.allowCellular"),
                isOn: $downloadSettings.allowCellularDownloads
            )
            .onChange(of: downloadSettings.allowCellularDownloads) {
                downloadManager?.refreshCellularAccessSetting()
            }
        } footer: {
            Text(String(localized: "settings.downloads.allowCellular.footer"))
        }
    }
}
#endif

#Preview {
    NavigationStack {
        DownloadSettingsView()
    }
    .appEnvironment(.preview)
}
#endif
