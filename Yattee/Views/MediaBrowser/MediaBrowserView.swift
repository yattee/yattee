//
//  MediaBrowserView.swift
//  Yattee
//
//  View for browsing files in a media source.
//

import SwiftUI

struct MediaBrowserView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let source: MediaSource
    let initialPath: String

    @Namespace private var sheetTransition
    @State private var currentPath: String
    @State private var files: [MediaFile] = []
    @State private var isLoading = false
    @State private var error: MediaSourceError?
    @State private var showOnlyPlayable: Bool
    @State private var sortOrder: MediaBrowserSortOrder
    @State private var sortAscending: Bool
    @State private var showViewOptions = false

    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    init(source: MediaSource, path: String = "/", showOnlyPlayable: Bool = false) {
        self.source = source
        self.initialPath = path
        _currentPath = State(initialValue: path)

        let defaults = UserDefaults.standard
        let key = "mediaBrowser.\(source.id.uuidString)"

        if let raw = defaults.string(forKey: "\(key).sortOrder"),
           let saved = MediaBrowserSortOrder(rawValue: raw) {
            _sortOrder = State(initialValue: saved)
        } else {
            _sortOrder = State(initialValue: .name)
        }

        _sortAscending = State(initialValue: defaults.object(forKey: "\(key).sortAscending") as? Bool ?? true)
        _showOnlyPlayable = State(initialValue: defaults.object(forKey: "\(key).showOnlyPlayable") as? Bool ?? showOnlyPlayable)
    }

    /// Files filtered and sorted based on current settings.
    private var displayedFiles: [MediaFile] {
        var result = files
        if showOnlyPlayable {
            result = result.filter { $0.isDirectory || $0.isPlayable }
        }
        return sortedFiles(result)
    }

    var body: some View {
        Group {
            if isLoading && files.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView {
                    Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button(String(localized: "common.retry")) {
                        Task { await loadFiles() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if files.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "mediaBrowser.emptyFolder"), systemImage: "folder")
                } description: {
                    Text(String(localized: "mediaBrowser.emptyFolder.description"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileList
            }
        }
        .navigationTitle(navigationTitle)
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbar {
            #if !os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        Task { await loadFiles() }
                    } label: {
                        Label(String(localized: "common.refresh"), systemImage: "arrow.clockwise")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(
                        String(localized: "viewOptions.title"),
                        systemImage: showOnlyPlayable
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .liquidGlassTransitionSource(id: "mediaBrowserViewOptions", in: sheetTransition)
            }
            #endif
        }
        .sheet(isPresented: $showViewOptions) {
            MediaBrowserViewOptionsSheet(
                sourceType: source.type,
                sortOrder: $sortOrder,
                sortAscending: $sortAscending,
                showOnlyPlayable: $showOnlyPlayable
            )
            .liquidGlassSheetContent(sourceID: "mediaBrowserViewOptions", in: sheetTransition)
        }
        .task {
            await loadFiles()
        }
        .onChange(of: sortOrder) { _, newValue in
            savePreference(newValue.rawValue, forKey: "sortOrder")
        }
        .onChange(of: sortAscending) { _, newValue in
            savePreference(newValue, forKey: "sortAscending")
        }
        .onChange(of: showOnlyPlayable) { _, newValue in
            savePreference(newValue, forKey: "showOnlyPlayable")
        }
    }

    private var navigationTitle: String {
        if currentPath == "/" || currentPath.isEmpty {
            return source.name
        }
        return (currentPath as NSString).lastPathComponent
    }

    private var fileList: some View {
        (listStyle == .inset ? ListBackgroundStyle.grouped.color : ListBackgroundStyle.plain.color)
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        sectionCard {
                            ForEach(Array(displayedFiles.enumerated()), id: \.element.id) { index, file in
                                let isLast = index == displayedFiles.count - 1

                                SourceListRow(isLast: isLast, listStyle: listStyle) {
                                    if file.isDirectory {
                                        NavigationLink(value: NavigationDestination.mediaBrowser(source, path: file.path, showOnlyPlayable: showOnlyPlayable)) {
                                            MediaFileRow(file: file, sortOrder: sortOrder)
                                        }
                                        .foregroundStyle(.primary)
                                    } else if file.isPlayable {
                                        playableFileRow(for: file)
                                    } else {
                                        MediaFileRow(file: file, sortOrder: sortOrder)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                }
            )
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if listStyle == .inset {
            LazyVStack(spacing: 0) {
                content()
            }
            .background(ListBackgroundStyle.card.color)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        } else {
            LazyVStack(spacing: 0) {
                content()
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Preferences

    private func savePreference(_ value: Any, forKey suffix: String) {
        UserDefaults.standard.set(value, forKey: "mediaBrowser.\(source.id.uuidString).\(suffix)")
    }

    // MARK: - Loading

    @MainActor
    private func loadFiles() async {
        guard let appEnvironment else { return }

        isLoading = true
        error = nil

        do {
            let loadedFiles: [MediaFile]

            switch source.type {
            case .webdav:
                let password = appEnvironment.mediaSourcesManager.password(for: source)
                loadedFiles = try await appEnvironment.webDAVClient.listFiles(
                    at: currentPath,
                    source: source,
                    password: password
                )

            case .smb:
                let password = appEnvironment.mediaSourcesManager.password(for: source)
                loadedFiles = try await appEnvironment.smbClient.listFiles(
                    at: currentPath,
                    source: source,
                    password: password
                )

            case .localFolder:
                loadedFiles = try await appEnvironment.localFileClient.listFiles(
                    at: currentPath,
                    source: source
                )
            }

            files = loadedFiles
            isLoading = false
        } catch let err as MediaSourceError {
            error = err
            isLoading = false
        } catch {
            self.error = .unknown(error.localizedDescription)
            isLoading = false
        }
    }

    private func sortedFiles(_ files: [MediaFile]) -> [MediaFile] {
        files.sorted { lhs, rhs in
            // Directories always first
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            let comparison: ComparisonResult
            switch sortOrder {
            case .name:
                comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .dateModified:
                let lhsDate = lhs.modifiedDate ?? .distantPast
                let rhsDate = rhs.modifiedDate ?? .distantPast
                comparison = lhsDate.compare(rhsDate)
            case .dateCreated:
                let lhsDate = lhs.createdDate ?? .distantPast
                let rhsDate = rhs.createdDate ?? .distantPast
                comparison = lhsDate.compare(rhsDate)
            }

            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    // MARK: - Playable row composition

    @ViewBuilder
    private func playableFileRow(for file: MediaFile) -> some View {
        #if os(tvOS)
        MediaFileTVOSTapButton(
            onPlay: { playFile(file) },
            onOpenInfo: { openInfo(for: file) }
        ) {
            MediaFileRow(file: file, sortOrder: sortOrder)
        }
        .videoContextMenu(video: file.toVideo(), context: .mediaBrowser)
        #else
        MediaFileRow(
            file: file,
            sortOrder: sortOrder,
            iconAreaModifier: { view in
                AnyView(
                    view.mediaFileRegionTap(
                        action: appEnvironment?.settingsManager.thumbnailTapAction ?? .playVideo,
                        onPlay: { playFile(file) },
                        onOpenInfo: { openInfo(for: file) }
                    )
                )
            },
            textAreaModifier: { view in
                AnyView(
                    view.mediaFileRegionTap(
                        action: appEnvironment?.settingsManager.textAreaTapAction ?? .openInfo,
                        onPlay: { playFile(file) },
                        onOpenInfo: { openInfo(for: file) }
                    )
                )
            }
        )
        .contentShape(Rectangle())
        .onTapGesture { playFile(file) }
        .videoContextMenu(video: file.toVideo(), context: .mediaBrowser)
        #endif
    }

    // MARK: - Playback

    private func openInfo(for file: MediaFile) {
        guard let appEnvironment else { return }

        let playableFiles = displayedFiles.filter { $0.isPlayable }
        let videos = playableFiles.map { $0.toVideo() }
        let index = playableFiles.firstIndex(where: { $0.id == file.id }) ?? 0
        let folderPath = (file.path as NSString).deletingLastPathComponent
        let folderName = (folderPath as NSString).lastPathComponent

        let context = VideoQueueContext(
            video: file.toVideo(),
            queueSource: .mediaBrowser(sourceID: source.id, folderPath: folderPath),
            sourceLabel: folderName.isEmpty ? source.name : folderName,
            videoList: videos,
            videoIndex: index,
            startTime: nil,
            loadMoreVideos: nil,
            mediaBrowserPlayback: MediaBrowserPlaybackInfo(
                source: source,
                allFilesInFolder: files
            )
        )

        appEnvironment.navigationCoordinator.navigate(
            to: .video(.loaded(file.toVideo()), queueContext: context)
        )
    }

    private func playFile(_ file: MediaFile) {
        guard let appEnvironment else { return }

        // Get all playable files in current sort order
        let playableFiles = displayedFiles.filter { $0.isPlayable }

        // Find the index of the tapped file in the playable files list
        guard let playableIndex = playableFiles.firstIndex(where: { $0.id == file.id }) else {
            return
        }

        // Use queue-based playback with all files in the folder
        // Stream and captions are resolved on-demand when each video plays
        appEnvironment.queueManager.playFromMediaBrowser(
            files: playableFiles,
            index: playableIndex,
            source: source,
            allFilesInFolder: files  // All files including subtitles for discovery
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MediaBrowserView(
            source: .webdav(name: "My NAS", url: URL(string: "https://nas.local:5006")!)
        )
    }
    .appEnvironment(.preview)
}
