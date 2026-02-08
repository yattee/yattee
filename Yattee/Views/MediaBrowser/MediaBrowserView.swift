//
//  MediaBrowserView.swift
//  Yattee
//
//  View for browsing files in a media source.
//

import SwiftUI

struct MediaBrowserView: View {
    let source: MediaSource
    let initialPath: String

    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition
    @State private var currentPath: String
    @State private var files: [MediaFile] = []
    @State private var isLoading = false
    @State private var error: MediaSourceError?
    @State private var showOnlyPlayable: Bool
    @State private var sortOrder: MediaBrowserSortOrder = .name
    @State private var sortAscending = true
    @State private var showViewOptions = false

    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    init(source: MediaSource, path: String = "/", showOnlyPlayable: Bool = false) {
        self.source = source
        self.initialPath = path
        _currentPath = State(initialValue: path)
        _showOnlyPlayable = State(initialValue: showOnlyPlayable)
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
            } else if files.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "mediaBrowser.emptyFolder"), systemImage: "folder")
                } description: {
                    Text(String(localized: "mediaBrowser.emptyFolder.description"))
                }
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
                        "View Options",
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
                sortOrder: $sortOrder,
                sortAscending: $sortAscending,
                showOnlyPlayable: $showOnlyPlayable,
                sourceType: source.type
            )
            .liquidGlassSheetContent(sourceID: "mediaBrowserViewOptions", in: sheetTransition)
        }
        .task {
            await loadFiles()
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
                                    } else {
                                        MediaFileRow(file: file, sortOrder: sortOrder) {
                                            if file.isPlayable {
                                                playFile(file)
                                            }
                                        }
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

    // MARK: - Playback

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
