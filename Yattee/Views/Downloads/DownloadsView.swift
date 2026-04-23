//
//  DownloadsView.swift
//  Yattee
//
//  Downloads management view.
//

import SwiftUI

#if !os(tvOS)
struct DownloadsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var selectedDownload: Download?
    @State private var failedDownloadToShow: Download?
    @State private var searchText = ""

    private var downloadManager: DownloadManager? {
        appEnvironment?.downloadManager
    }

    private var downloadSettings: DownloadSettings? {
        appEnvironment?.downloadSettings
    }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    var body: some View {
        Group {
            if let manager = downloadManager, let settings = downloadSettings {
                downloadsList(manager, settings: settings)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(String(localized: "downloads.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let settings = downloadSettings {
                    sortAndGroupMenu(settings)
                }
            }
        }
    }

    // MARK: - Downloads List

    @ViewBuilder
    private func downloadsList(_ manager: DownloadManager, settings: DownloadSettings) -> some View {
        let hasGroupedContent = settings.groupByChannel || settings.sortOption == .name

        Group {
            if hasGroupedContent {
                // Grouped content needs separate cards per group
                groupedDownloadsList(manager, settings: settings)
            } else {
                // Flat list uses single card
                flatDownloadsList(manager, settings: settings)
            }
        }
        .searchable(text: $searchText, prompt: Text(String(localized: "downloads.search.placeholder")))
        .onChange(of: selectedDownload) { _, newValue in
            if let download = newValue {
                if let result = downloadManager?.videoAndStream(for: download) {
                    appEnvironment?.playerService.openVideo(result.video, stream: result.stream, audioStream: result.audioStream, download: download)
                }
                selectedDownload = nil
            }
        }
        .alert(
            String(localized: "downloads.status.failed"),
            isPresented: .init(
                get: { failedDownloadToShow != nil },
                set: { if !$0 { failedDownloadToShow = nil } }
            )
        ) {
            Button(String(localized: "downloads.retry")) {
                if let download = failedDownloadToShow {
                    Task { await manager.resume(download) }
                }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            if let download = failedDownloadToShow {
                Text(download.error ?? String(localized: "downloads.error.unknown"))
            }
        }
    }

    // MARK: - Flat Downloads List (Separate Cards for Active/Completed)

    @ViewBuilder
    private func flatDownloadsList(_ manager: DownloadManager, settings: DownloadSettings) -> some View {
        // NOTE: Active and Completed sections are separate views to isolate observation scopes.
        // This prevents completed section from re-rendering when active downloads progress updates.
        // Active and completed downloads are in separate cards for visual clarity.
        let backgroundStyle: ListBackgroundStyle = listStyle == .inset ? .grouped : .plain

        backgroundStyle.color
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 16)

                        // Active downloads in its own card
                        ActiveDownloadsSectionContentView(
                            manager: manager,
                            searchText: searchText,
                            listStyle: listStyle,
                            isGroupedMode: true,  // Always use card mode for active downloads
                            failedDownloadToShow: $failedDownloadToShow
                        )

                        // Completed downloads in its own card
                        CompletedDownloadsSectionContentView(
                            manager: manager,
                            settings: settings,
                            searchText: searchText,
                            listStyle: listStyle,
                            isGroupedMode: false
                        )

                        // Empty state
                        DownloadsEmptyStateView(
                            manager: manager,
                            searchText: searchText
                        )
                    }
                }
            )
    }

    // MARK: - Grouped Downloads List (Separate Cards per Group)

    @ViewBuilder
    private func groupedDownloadsList(_ manager: DownloadManager, settings: DownloadSettings) -> some View {
        let backgroundStyle: ListBackgroundStyle = listStyle == .inset ? .grouped : .plain

        backgroundStyle.color
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Spacer().frame(height: 16)

                        // Active downloads in its own card (if any)
                        ActiveDownloadsSectionContentView(
                            manager: manager,
                            searchText: searchText,
                            listStyle: listStyle,
                            isGroupedMode: true,
                            failedDownloadToShow: $failedDownloadToShow
                        )

                        // Completed downloads with separate cards per group
                        CompletedDownloadsSectionContentView(
                            manager: manager,
                            settings: settings,
                            searchText: searchText,
                            listStyle: listStyle,
                            isGroupedMode: true
                        )

                        // Empty state
                        DownloadsEmptyStateView(
                            manager: manager,
                            searchText: searchText
                        )
                    }
                }
            )
    }

    // MARK: - Sort and Group Menu

    @ViewBuilder
    private func sortAndGroupMenu(_ settings: DownloadSettings) -> some View {
        Menu {
            // Sort options
            Section {
                Picker(selection: Binding(
                    get: { settings.sortOption },
                    set: { settings.sortOption = $0 }
                )) {
                    ForEach(DownloadSortOption.allCases, id: \.self) { option in
                        Label(option.displayName, systemImage: option.systemImage)
                            .tag(option)
                    }
                } label: {
                    Label(String(localized: "downloads.sort.title"), systemImage: "arrow.up.arrow.down")
                }

                // Sort direction
                Button {
                    settings.sortDirection.toggle()
                } label: {
                    Label(
                        settings.sortDirection == .ascending
                            ? String(localized: "downloads.sort.ascending")
                            : String(localized: "downloads.sort.descending"),
                        systemImage: settings.sortDirection.systemImage
                    )
                }
            }

            // Grouping
            Section {
                Toggle(isOn: Binding(
                    get: { settings.groupByChannel },
                    set: { settings.groupByChannel = $0 }
                )) {
                    Label(String(localized: "downloads.groupByChannel"), systemImage: "person.2")
                }
            }
        } label: {
            Label(String(localized: "downloads.sortAndGroup"), systemImage: "line.3.horizontal.decrease.circle")
        }
    }

}

// MARK: - Active Downloads Section Content View (Isolated Observation Scope)

/// Separate view for active downloads to isolate @Observable tracking.
/// Only accesses manager.activeDownloads, so won't re-render when completedDownloads changes.
/// Generates rows directly for VideoListContainer (no Section wrapper).
private struct ActiveDownloadsSectionContentView: View {
    let manager: DownloadManager
    let searchText: String
    let listStyle: VideoListStyle
    let isGroupedMode: Bool
    @Binding var failedDownloadToShow: Download?

    private var activeFiltered: [Download] {
        guard !searchText.isEmpty else { return manager.activeDownloads }
        let query = searchText.lowercased()
        return manager.activeDownloads.filter { download in
            download.title.lowercased().contains(query) ||
            download.channelName.lowercased().contains(query) ||
            download.videoID.videoID.lowercased().contains(query)
        }
    }

    var body: some View {
        if !activeFiltered.isEmpty {
            if isGroupedMode {
                // Grouped mode: rows in their own card
                VideoListContent(listStyle: listStyle) {
                    activeDownloadRows
                }
            } else {
                // Flat mode: rows inline
                activeDownloadRows
            }
        }
    }

    @ViewBuilder
    private var activeDownloadRows: some View {
        ForEach(Array(activeFiltered.enumerated()), id: \.element.id) { index, download in
            VideoListRow(
                isLast: index == activeFiltered.count - 1,
                rowStyle: .regular,
                listStyle: listStyle
            ) {
                DownloadRowView(
                    download: download,
                    isActive: true
                )
                .onTapGesture {
                    if download.status == .failed {
                        failedDownloadToShow = download
                    }
                }
            }
            .swipeActions(actionsArray: swipeActionsFor(download))
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, listStyle == .inset ? 16 : 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }

    // MARK: - Swipe Actions

    private func swipeActionsFor(_ download: Download) -> [SwipeAction] {
        var actions: [SwipeAction] = []

        // Pause/Resume action based on status
        if download.status == .downloading {
            actions.append(SwipeAction(
                symbolImage: "pause.fill",
                tint: .white,
                background: .orange
            ) { reset in
                Task { await manager.pause(download) }
                reset()
            })
        } else if download.status == .paused || download.status == .failed {
            actions.append(SwipeAction(
                symbolImage: "play.fill",
                tint: .white,
                background: .green
            ) { reset in
                Task { await manager.resume(download) }
                reset()
            })
        }

        // Cancel action (always present)
        actions.append(SwipeAction(
            symbolImage: "xmark.circle.fill",
            tint: .white,
            background: .red
        ) { reset in
            Task { await manager.cancel(download) }
            reset()
        })

        return actions
    }
}

// MARK: - Completed Downloads Section Content View (Isolated Observation Scope)

/// Separate view for completed downloads to isolate @Observable tracking.
/// Only accesses manager.completedDownloads, so won't re-render when activeDownloads progress updates.
/// Generates rows directly for VideoListContainer (no Section wrapper).
private struct CompletedDownloadsSectionContentView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let manager: DownloadManager
    let settings: DownloadSettings
    let searchText: String
    let listStyle: VideoListStyle
    let isGroupedMode: Bool

    private var completedFiltered: [Download] {
        guard !searchText.isEmpty else { return manager.completedDownloads }
        let query = searchText.lowercased()
        return manager.completedDownloads.filter { download in
            download.title.lowercased().contains(query) ||
            download.channelName.lowercased().contains(query) ||
            download.videoID.videoID.lowercased().contains(query)
        }
    }

    var body: some View {
        if !completedFiltered.isEmpty {
            if settings.groupByChannel {
                groupedByChannelContent(completedFiltered)
            } else if settings.sortOption == .name {
                groupedByLetterContent(completedFiltered)
            } else {
                flatListContent(completedFiltered)
            }
        }
    }

    // MARK: - Grouped by Channel

    @ViewBuilder
    private func groupedByChannelContent(_ downloads: [Download]) -> some View {
        let grouped = settings.groupedByChannel(downloads)
        let allDownloadsInOrder = grouped.flatMap { $0.downloads }
        let downloadsDir = manager.downloadsDirectory()
        let videoList = allDownloadsInOrder.map { $0.toVideo(downloadsDirectory: downloadsDir) }
        var runningIndex = 0

        ForEach(Array(grouped.enumerated()), id: \.element.channelID) { groupIndex, group in
            let baseIndex = runningIndex
            let _ = { runningIndex += group.downloads.count }()

            // Channel header OUTSIDE the card
            channelSectionHeader(group.channel, channelID: group.channelID, downloads: group.downloads)

            if isGroupedMode {
                // Each group in its own VideoListContent card
                VideoListContent(listStyle: listStyle) {
                    ForEach(Array(group.downloads.enumerated()), id: \.element.id) { localIndex, download in
                        completedDownloadRow(
                            download,
                            videoList: videoList,
                            index: baseIndex + localIndex,
                            isLast: localIndex == group.downloads.count - 1
                        )
                    }
                }
            } else {
                // Flat mode: rows inline
                ForEach(Array(group.downloads.enumerated()), id: \.element.id) { localIndex, download in
                    let isLastInGroup = localIndex == group.downloads.count - 1
                    let isLastGroup = groupIndex == grouped.count - 1
                    completedDownloadRow(
                        download,
                        videoList: videoList,
                        index: baseIndex + localIndex,
                        isLast: isLastInGroup && isLastGroup
                    )
                }
            }
        }
    }

    // MARK: - Grouped by Letter

    @ViewBuilder
    private func groupedByLetterContent(_ downloads: [Download]) -> some View {
        let sortedDownloads = settings.sorted(downloads)
        let groupedByLetter = groupDownloadsByFirstLetter(sortedDownloads, ascending: settings.sortDirection == .ascending)
        let allDownloadsInOrder = groupedByLetter.flatMap { $0.downloads }
        let downloadsDir = manager.downloadsDirectory()
        let videoList = allDownloadsInOrder.map { $0.toVideo(downloadsDirectory: downloadsDir) }
        var runningIndex = 0

        ForEach(Array(groupedByLetter.enumerated()), id: \.element.letter) { groupIndex, group in
            let baseIndex = runningIndex
            let _ = { runningIndex += group.downloads.count }()

            // Letter header OUTSIDE the card
            letterSectionHeader(group.letter)

            if isGroupedMode {
                // Each group in its own VideoListContent card
                VideoListContent(listStyle: listStyle) {
                    ForEach(Array(group.downloads.enumerated()), id: \.element.id) { localIndex, download in
                        completedDownloadRow(
                            download,
                            videoList: videoList,
                            index: baseIndex + localIndex,
                            isLast: localIndex == group.downloads.count - 1
                        )
                    }
                }
            } else {
                // Flat mode: rows inline
                ForEach(Array(group.downloads.enumerated()), id: \.element.id) { localIndex, download in
                    let isLastInGroup = localIndex == group.downloads.count - 1
                    let isLastGroup = groupIndex == groupedByLetter.count - 1
                    completedDownloadRow(
                        download,
                        videoList: videoList,
                        index: baseIndex + localIndex,
                        isLast: isLastInGroup && isLastGroup
                    )
                }
            }
        }
    }

    // MARK: - Flat List

    @ViewBuilder
    private func flatListContent(_ downloads: [Download]) -> some View {
        let sortedDownloads = settings.sorted(downloads)
        let downloadsDir = manager.downloadsDirectory()
        let videoList = sortedDownloads.map { $0.toVideo(downloadsDirectory: downloadsDir) }

        // Flat list content wrapped in its own card
        VideoListContent(listStyle: listStyle) {
            ForEach(Array(sortedDownloads.enumerated()), id: \.element.id) { index, download in
                completedDownloadRow(
                    download,
                    videoList: videoList,
                    index: index,
                    isLast: index == sortedDownloads.count - 1
                )
            }
        }
    }

    // MARK: - Section Headers

    private func letterSectionHeader(_ letter: String) -> some View {
        Text(letter)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, listStyle == .inset ? 16 : 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }

    @ViewBuilder
    private func channelSectionHeader(_ channel: String, channelID: String, downloads: [Download]) -> some View {
        let contentSource = downloads.first?.toVideo().id.source ?? .global(provider: ContentSource.youtubeProvider)
        NavigationLink(value: NavigationDestination.channel(channelID, contentSource)) {
            HStack(spacing: 4) {
                Text(channel)
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .foregroundStyle(Color.accentColor)
        }
        .zoomTransitionSource(id: channelID)
        .buttonStyle(.plain)
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, listStyle == .inset ? 16 : 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Row and Footer

    @ViewBuilder
    private func completedDownloadRow(_ download: Download, videoList: [Video], index: Int, isLast: Bool) -> some View {
        VideoListRow(
            isLast: isLast,
            rowStyle: .regular,
            listStyle: listStyle
        ) {
            DownloadRowView(
                download: download,
                isActive: false,
                queueSource: .manual,
                sourceLabel: String(localized: "queue.source.downloads"),
                videoList: videoList,
                videoIndex: index,
                loadMoreVideos: loadMoreDownloadsCallback
            )
        }
        .videoSwipeActions(
            video: download.toVideo(downloadsDirectory: manager.downloadsDirectory()),
            fixedActions: [
                SwipeAction(
                    symbolImage: "trash.fill",
                    tint: .white,
                    background: .red
                ) { reset in
                    Task { await manager.delete(download) }
                    reset()
                }
            ]
        )
    }

    @Sendable
    private func loadMoreDownloadsCallback() async throws -> ([Video], String?) {
        return ([], nil)
    }

    // MARK: - Helpers

    private func sectionIndexLabel(for text: String) -> String {
        guard let firstChar = text.first else { return "#" }
        let uppercased = String(firstChar).uppercased()
        return uppercased.first?.isLetter == true ? uppercased : "#"
    }

    private func groupDownloadsByFirstLetter(_ downloads: [Download], ascending: Bool) -> [(letter: String, downloads: [Download])] {
        let grouped = Dictionary(grouping: downloads) { download -> String in
            sectionIndexLabel(for: download.title)
        }

        return grouped.map { (letter, downloads) in
            (letter: letter, downloads: downloads)
        }
        .sorted { ascending ? $0.letter < $1.letter : $0.letter > $1.letter }
    }
}

// MARK: - Downloads Empty State View (Isolated Observation Scope)

/// Separate view for empty state to avoid re-rendering main content when checking isEmpty.
private struct DownloadsEmptyStateView: View {
    let manager: DownloadManager
    let searchText: String

    private var hasActiveDownloads: Bool {
        !manager.activeDownloads.isEmpty
    }

    private var hasCompletedDownloads: Bool {
        !manager.completedDownloads.isEmpty
    }

    private var isEmpty: Bool {
        if searchText.isEmpty {
            return !hasActiveDownloads && !hasCompletedDownloads
        }
        let query = searchText.lowercased()
        let hasMatchingActive = manager.activeDownloads.contains { download in
            download.title.lowercased().contains(query) ||
            download.channelName.lowercased().contains(query) ||
            download.videoID.videoID.lowercased().contains(query)
        }
        let hasMatchingCompleted = manager.completedDownloads.contains { download in
            download.title.lowercased().contains(query) ||
            download.channelName.lowercased().contains(query) ||
            download.videoID.videoID.lowercased().contains(query)
        }
        return !hasMatchingActive && !hasMatchingCompleted
    }

    var body: some View {
        if isEmpty {
            if !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 60)
            } else {
                ContentUnavailableView {
                    Label(String(localized: "downloads.empty.title"), systemImage: "arrow.down.circle")
                } description: {
                    Text(String(localized: "downloads.empty.description"))
                }
                .padding(.top, 60)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DownloadsView()
    }
    .appEnvironment(.preview)
}
#endif
