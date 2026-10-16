//
//  OpenedLinksView.swift
//  Yattee
//
//  Several links opened from Open Link, shown like mixed search results:
//  videos, playlists and channels in the order they were entered, filled in
//  as each link resolves.
//

import SwiftUI

struct OpenedLinksView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    #if os(tvOS)
    @Environment(\.dismiss) private var dismiss
    #endif
    @AppStorage("searchRowStyle") private var rowStyle: VideoRowStyle = .regular

    @State private var viewModel: OpenedLinksViewModel

    #if !os(tvOS)
    @State private var showingDownloadSheet = false
    #endif

    init(urls: [URL]) {
        _viewModel = State(initialValue: OpenedLinksViewModel(urls: urls))
    }

    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    private var title: String {
        String(localized: "openedLinks.title")
    }

    var body: some View {
        content
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Buttons disable themselves: a macOS toolbar item doesn't
                    // re-render on state changes, menu content does on open.
                    Menu {
                        batchActions
                    } label: {
                        Label(String(localized: "openedLinks.actions"), systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingDownloadSheet) {
                BatchDownloadQualitySheet(videoCount: viewModel.videoLinks.count) { quality, includeSubtitles in
                    Task { await download(quality: quality, includeSubtitles: includeSubtitles) }
                }
            }
            #endif
            .onAppear {
                guard let appEnvironment else { return }
                viewModel.start(appEnvironment: appEnvironment)
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(tvOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    batchActions

                    // The batch buttons stay disabled until a video resolves,
                    // and loading or failed rows are not focusable: with every
                    // link still loading or failed, this is the only thing the
                    // remote can land on.
                    if viewModel.videos.isEmpty {
                        Button(String(localized: "common.done")) {
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 48)

                resultsList
            }
        }
        .scrollClipDisabled()
        #else
        (listStyle == .inset ? ListBackgroundStyle.grouped : ListBackgroundStyle.plain).color
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    resultsList
                }
            )
        #endif
    }

    private var resultsList: some View {
        VideoListContent(listStyle: listStyle) {
            ForEach(viewModel.links) { link in
                VideoListRow(
                    isLast: link.id == viewModel.links.last?.id,
                    rowStyle: rowStyle,
                    listStyle: listStyle,
                    contentWidth: isChannel(link) ? rowStyle.thumbnailHeight : nil
                ) {
                    row(for: link)
                }
            }
        }
    }

    private func isChannel(_ link: OpenedLink) -> Bool {
        if case .channel = link.state { return true }
        return false
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for link: OpenedLink) -> some View {
        switch link.state {
        case .loading:
            LinkStatusRow(url: link.url, message: nil, style: rowStyle, status: .loading)

        case .video(let video):
            let videos = viewModel.videos
            VideoRowView(video: video, style: rowStyle)
                .tappableVideo(
                    video,
                    queueSource: .manual,
                    sourceLabel: title,
                    videoList: videos,
                    videoIndex: videos.firstIndex(where: { $0.id == video.id })
                )
                #if !os(tvOS)
                .videoSwipeActions(video: video)
                #endif

        case .playlist(let playlist, _):
            NavigationLink(value: NavigationDestination.playlist(.remote(playlist.id, instance: nil, title: playlist.title))) {
                SearchPlaylistRowView(playlist: playlist, style: rowStyle)
                    .contentShape(Rectangle())
            }
            .zoomTransitionSource(id: playlist.id)
            .buttonStyle(.plain)

        case .channel(let channel, let destination):
            NavigationLink(value: destination) {
                ChannelRowView(channel: channel, style: rowStyle)
                    .contentShape(Rectangle())
            }
            .zoomTransitionSource(id: channel.id.channelID)
            .buttonStyle(.plain)

        case .unresolved(let destination, let message):
            NavigationLink(value: destination) {
                LinkStatusRow(url: link.url, message: message, style: rowStyle, status: .unresolved)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

        case .failed(let message):
            LinkStatusRow(url: link.url, message: message, style: rowStyle, status: .failed)
        }
    }

    // MARK: - Batch Actions

    @ViewBuilder
    private var batchActions: some View {
        let noVideos = viewModel.videos.isEmpty

        Button {
            playAll()
        } label: {
            Label(String(localized: "openedLinks.playAll"), systemImage: "play.fill")
        }
        .disabled(noVideos)

        if appEnvironment?.settingsManager.queueEnabled == true {
            Button {
                addAllToQueue()
            } label: {
                Label(String(localized: "openedLinks.addAllToQueue"), systemImage: "text.badge.plus")
            }
            .disabled(noVideos)
        }

        Button {
            bookmarkAll()
        } label: {
            Label(String(localized: "openedLinks.bookmarkAll"), systemImage: "bookmark")
        }
        .disabled(noVideos)

        #if !os(tvOS)
        Button {
            startDownload()
        } label: {
            Label(String(localized: "openedLinks.downloadAll"), systemImage: "arrow.down.circle")
        }
        .disabled(noVideos)
        #endif
    }

    private func playAll() {
        let videos = viewModel.videos
        guard let appEnvironment, !videos.isEmpty else { return }
        appEnvironment.queueManager.playFromList(
            videos: videos,
            index: 0,
            queueSource: .manual,
            sourceLabel: title
        )
    }

    private func addAllToQueue() {
        let videos = viewModel.videos
        guard let appEnvironment, !videos.isEmpty else { return }
        appEnvironment.queueManager.addToQueue(videos, queueSource: .manual)
        appEnvironment.toastManager.showSuccess(
            String(localized: "openLink.queuedSuccess.title"),
            subtitle: String(localized: "openLink.queuedSuccess.subtitle \(videos.count)")
        )
    }

    private func bookmarkAll() {
        let videos = viewModel.videos
        guard let appEnvironment, !videos.isEmpty else { return }
        for video in videos {
            appEnvironment.dataManager.addBookmark(for: video)
        }
        appEnvironment.toastManager.showSuccess(
            String(localized: "openedLinks.bookmarked.title"),
            subtitle: String(localized: "openedLinks.bookmarked.subtitle \(videos.count)")
        )
    }

    #if !os(tvOS)
    private func startDownload() {
        guard let appEnvironment, !viewModel.videoLinks.isEmpty else { return }
        let settings = appEnvironment.downloadSettings
        if settings.preferredDownloadQuality == .ask {
            showingDownloadSheet = true
        } else {
            Task {
                await download(
                    quality: settings.preferredDownloadQuality,
                    includeSubtitles: settings.includeSubtitlesInAutoDownload
                )
            }
        }
    }

    private func download(quality: DownloadQuality, includeSubtitles: Bool) async {
        guard let appEnvironment else { return }
        let (succeeded, failed) = await LinkVideoResolver(appEnvironment: appEnvironment)
            .downloadLinks(viewModel.videoLinks, quality: quality, includeSubtitles: includeSubtitles)

        if failed == 0 {
            appEnvironment.toastManager.showSuccess(
                String(localized: "openLink.downloadQueued.title"),
                subtitle: String(localized: "openLink.downloadQueued.subtitle \(succeeded)")
            )
        } else {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.downloadPartial.title"),
                subtitle: String(localized: "openLink.downloadPartial.subtitle \(succeeded) \(failed)")
            )
        }
    }
    #endif
}

// MARK: - Link Status Row

/// Placeholder row for a link that is loading, failed, or couldn't be
/// previewed but still opens a screen.
private struct LinkStatusRow: View {
    enum Status {
        case loading
        case unresolved
        case failed
    }

    let url: URL
    let message: String?
    let style: VideoRowStyle
    let status: Status

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                icon
            }
            .frame(width: style.thumbnailHeight * 16 / 9, height: style.thumbnailHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(url.host ?? url.absoluteString)
                    .font(.headline)
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let message, status == .failed || message != url.absoluteString {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(status == .failed ? .red : .secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if status == .unresolved {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .loading:
            ProgressView()
        case .unresolved:
            Image(systemName: "link")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }
}
