//
//  DownloadsStorageView.swift
//  Yattee
//
//  View for managing downloaded video storage.
//

import SwiftUI

#if !os(tvOS)
struct DownloadsStorageView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var showingDeleteWatchedConfirmation = false
    @State private var showingDeleteAllConfirmation = false

    private var downloadManager: DownloadManager? {
        appEnvironment?.downloadManager
    }

    private var dataManager: DataManager? {
        appEnvironment?.dataManager
    }

    /// Downloads sorted by file size (largest first).
    private var completedDownloads: [Download] {
        (downloadManager?.completedDownloads ?? []).sorted { $0.totalBytes > $1.totalBytes }
    }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // MARK: - Computed Properties

    /// Downloads that have been fully watched.
    private var watchedDownloads: [Download] {
        completedDownloads.filter { download in
            dataManager?.watchEntry(for: download.videoID.videoID)?.isFinished ?? false
        }
    }

    /// Total size of watched downloads in bytes.
    private var watchedDownloadsSize: Int64 {
        watchedDownloads.reduce(0) { $0 + $1.totalBytes }
    }

    /// Total size of all downloads in bytes.
    private var allDownloadsSize: Int64 {
        completedDownloads.reduce(0) { $0 + $1.totalBytes }
    }

    /// Set of watched video IDs for bulk deletion.
    private var watchedVideoIDs: Set<String> {
        Set(watchedDownloads.map { $0.videoID.videoID })
    }

    var body: some View {
        Group {
            if completedDownloads.isEmpty {
                emptyStateView
            } else {
                downloadsList
            }
        }
        .navigationTitle(String(localized: "settings.downloads.storage.title"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !completedDownloads.isEmpty {
                    deleteMenu
                }
            }
        }
        .confirmationDialog(
            String(localized: "settings.downloads.storage.deleteWatched"),
            isPresented: $showingDeleteWatchedConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.downloads.storage.deleteWatched"), role: .destructive) {
                Task {
                    await downloadManager?.deleteWatchedDownloads(watchedVideoIDs: watchedVideoIDs)
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("settings.downloads.storage.deleteWatched.message \(watchedDownloads.count) \(formatBytes(watchedDownloadsSize))")
        }
        .presentationCompactAdaptation(.sheet)
        .confirmationDialog(
            String(localized: "settings.downloads.storage.deleteAll"),
            isPresented: $showingDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "settings.downloads.storage.deleteAll"), role: .destructive) {
                Task {
                    await downloadManager?.deleteAllCompleted()
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("settings.downloads.storage.deleteAll.message \(completedDownloads.count) \(formatBytes(allDownloadsSize))")
        }
        .presentationCompactAdaptation(.sheet)
    }

    // MARK: - Delete Menu

    @ViewBuilder
    private var deleteMenu: some View {
        Menu {
            if !watchedDownloads.isEmpty {
                Button(role: .destructive) {
                    showingDeleteWatchedConfirmation = true
                } label: {
                    Label(
                        String(localized: "settings.downloads.storage.deleteWatched") + " (\(watchedDownloads.count), \(formatBytes(watchedDownloadsSize)))",
                        systemImage: "eye.fill"
                    )
                }
            }

            Button(role: .destructive) {
                showingDeleteAllConfirmation = true
            } label: {
                Label(
                    String(localized: "settings.downloads.storage.deleteAll") + " (\(completedDownloads.count), \(formatBytes(allDownloadsSize)))",
                    systemImage: "trash"
                )
            }
        } label: {
            Label(String(localized: "common.delete"), systemImage: "trash")
        }
    }

    // MARK: - Downloads List

    @ViewBuilder
    private var downloadsList: some View {
        let backgroundStyle: ListBackgroundStyle = listStyle == .inset ? .grouped : .plain

        backgroundStyle.color
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 16)

                        VideoListContent(listStyle: listStyle) {
                            ForEach(Array(completedDownloads.enumerated()), id: \.element.id) { index, download in
                                storageRow(download, isLast: index == completedDownloads.count - 1)
                            }
                        }
                    }
                }
            )
    }

    // MARK: - Storage Row

    @ViewBuilder
    private func storageRow(_ download: Download, isLast: Bool) -> some View {
        let video = download.toVideo(downloadsDirectory: downloadManager?.downloadsDirectory())
        let isWatched = dataManager?.watchEntry(for: download.videoID.videoID)?.isFinished ?? false

        VideoListRow(
            isLast: isLast,
            rowStyle: .regular,
            listStyle: listStyle
        ) {
            HStack(spacing: 12) {
                // Thumbnail with watched checkmark overlay
                DeArrowVideoThumbnail(
                    video: video,
                    duration: video.formattedDuration
                )
                .frame(width: 120, height: 68)

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                        .font(.subheadline)
                        .lineLimit(2)

                    Text(download.channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(formatBytes(download.totalBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isWatched {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .swipeActions(actionsArray: [
            SwipeAction(
                symbolImage: "trash.fill",
                tint: .white,
                background: .red
            ) { reset in
                Task { await downloadManager?.delete(download) }
                reset()
            }
        ])
        .contextMenu {
            Button(role: .destructive) {
                Task { await downloadManager?.delete(download) }
            } label: {
                Label(String(localized: "common.delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "settings.downloads.storage.empty"), systemImage: "arrow.down.circle")
        } description: {
            Text(String(localized: "settings.downloads.storage.empty.description"))
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DownloadsStorageView()
    }
    .appEnvironment(.preview)
}
#endif
