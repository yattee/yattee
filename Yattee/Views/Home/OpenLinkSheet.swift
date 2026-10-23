//
//  OpenLinkSheet.swift
//  Yattee
//
//  Sheet for entering links: Load shows a single link's video, playlist or
//  channel screen; Play and Download act on video links directly (YouTube,
//  PeerTube, direct media, or anything Yattee Server's yt-dlp extracts).
//  Supports multiple URLs (one per line) with batch processing.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Extraction Item Model

/// Tracks extraction status for each URL in batch processing.
private struct ExtractedItem: Identifiable {
    let id = UUID()
    let url: URL
    var displayHost: String { url.host ?? url.absoluteString }
    var status: ExtractionStatus = .pending
    var video: Video?
    var streams: [Stream] = []
    var captions: [Caption] = []
    var storyboards: [Storyboard] = []
}

private enum ExtractionStatus {
    case pending
    case extracting
    case success
    case failed(String)
}

// MARK: - OpenLinkSheet

/// Sheet for entering URLs to play or download from external sites.
/// Supports multiple URLs (one per line, max 200).
struct OpenLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prefilledURL: URL?

    init(prefilledURL: URL? = nil) {
        self.prefilledURL = prefilledURL
    }

    var body: some View {
        #if os(macOS)
        OpenLinkFormView(prefilledURL: prefilledURL, onRequestDismiss: { dismiss() })
            .frame(minWidth: 520, minHeight: 440)
        #else
        NavigationStack {
            OpenLinkFormView(prefilledURL: prefilledURL, onRequestDismiss: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel")) {
                            dismiss()
                        }
                    }
                }
        }
        #endif
    }
}

// MARK: - OpenLinkView

/// Standalone view for entering URLs — used as a tab root (e.g. tvOS sidebar).
/// Not wrapped in a NavigationStack; the containing tab provides one.
struct OpenLinkView: View {
    var body: some View {
        OpenLinkFormView(prefilledURL: nil, onRequestDismiss: nil)
    }
}

// MARK: - OpenLinkFormView

/// Shared form body used by both OpenLinkSheet (sheet) and OpenLinkView (tab root).
struct OpenLinkFormView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let onRequestDismiss: (() -> Void)?

    @State private var urlText: String
    @State private var clipboardURLs: [URL] = []
    @FocusState private var isTextEditorFocused: Bool

    // Extraction state
    @State private var isExtracting = false
    @State private var extractedItems: [ExtractedItem] = []
    @State private var hasErrors = false

    // Download flow states
    @State private var showingDownloadSheet = false
    @State private var pendingDownloadItems: [ExtractedItem] = []

    /// Maximum number of URLs allowed.
    fileprivate static let maxURLs = 200

    init(prefilledURL: URL?, onRequestDismiss: (() -> Void)?) {
        self.onRequestDismiss = onRequestDismiss
        _urlText = State(initialValue: prefilledURL?.absoluteString ?? "")
    }

    private func dismissIfRequested() {
        onRequestDismiss?()
    }

    var body: some View {
        platformBody
            .onAppear {
                checkClipboard()
                if urlText.isEmpty {
                    isTextEditorFocused = true
                }
            }
            #if !os(tvOS)
            .sheet(isPresented: $showingDownloadSheet, onDismiss: {
                // Close sheet when download sheet is dismissed (if no errors and we're in sheet mode)
                if !hasErrors {
                    dismissIfRequested()
                }
            }) {
                BatchDownloadQualitySheet(videoCount: pendingDownloadItems.count) { quality, includeSubtitles in
                    Task {
                        await downloadPendingItems(quality: quality, includeSubtitles: includeSubtitles)
                    }
                }
            }
            #endif
    }

    @ViewBuilder
    private var platformBody: some View {
        #if os(macOS)
        macOSBody
        #else
        Form {
            urlInputSection
            extractionResultsSection
            actionButtonsSection
            yatteeServerWarningSection
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "openLink.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        #endif
        #endif
    }

    #if os(macOS)
    @ViewBuilder
    private var macOSBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "openLink.title"))
                .font(.title3)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $urlText)
                    .font(.system(.body, design: .monospaced))
                    .focused($isTextEditorFocused)
                    .disabled(isExtracting)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 90, maxHeight: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)
                    )

                HStack {
                    Text(supportedSitesHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isTooManyURLs {
                        Label(
                            String(localized: "openLink.tooManyUrls \(Self.maxURLs)"),
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .font(.caption)
                    } else if urlCount > 0 {
                        Text(String(localized: "openLink.urlCount \(urlCount)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !clipboardURLs.isEmpty, !isExtracting {
                let clipboardText = clipboardURLs.map(\.absoluteString).joined(separator: "\n")
                if clipboardText != urlText {
                    Button {
                        urlText = clipboardText
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard")
                            if clipboardURLs.count > 1 {
                                Text(String(localized: "openLink.pasteMultiple \(clipboardURLs.count)"))
                            } else {
                                Text(String(localized: "openLink.pasteClipboard"))
                            }
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(clipboardURLs.first?.host ?? "")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }

            if !extractedItems.isEmpty {
                Divider()
                macOSResultsList
            }

            if !hasYatteeServer, hasExternalURLs, !isExtracting {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "openLink.yatteeServerNotConfigured"))
                            .font(.subheadline)
                        Text(String(localized: "openLink.yatteeServerMessage"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if onRequestDismiss != nil {
                    Button(String(localized: "common.cancel")) {
                        onRequestDismiss?()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if isExtracting {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "openLink.extracting"))
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    if allLinksAreVideos {
                        Button {
                            isTextEditorFocused = false
                            Task { await downloadAllURLs() }
                        } label: {
                            Label(
                                isMultipleURLs
                                    ? String(localized: "openLink.downloadAll")
                                    : String(localized: "openLink.download"),
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .disabled(!isValidInput)

                        Button {
                            isTextEditorFocused = false
                            Task { await openAllURLs() }
                        } label: {
                            Label(
                                isMultipleURLs
                                    ? String(localized: "openLink.openAll")
                                    : String(localized: "openLink.open"),
                                systemImage: "play.fill"
                            )
                        }
                        .disabled(!isValidInput)
                    }

                    Button {
                        isTextEditorFocused = false
                        Task { await loadURLs() }
                    } label: {
                        Label(loadButtonTitle, systemImage: "arrow.right.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isValidInput)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var macOSResultsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isExtracting {
                let processed = extractedItems.filter { item in
                    if case .pending = item.status { return false }
                    return true
                }.count
                Text(String(localized: "openLink.extractingProgress \(processed) \(extractedItems.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "openLink.results"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(extractedItems) { item in
                        HStack(spacing: 10) {
                            Group {
                                switch item.status {
                                case .pending:
                                    Image(systemName: "circle").foregroundStyle(.secondary)
                                case .extracting:
                                    ProgressView().controlSize(.small)
                                case .success:
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                case .failed:
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                }
                            }
                            .frame(width: 18)

                            VStack(alignment: .leading, spacing: 1) {
                                if let video = item.video {
                                    Text(video.title).lineLimit(1)
                                    Text(item.displayHost)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                } else {
                                    Text(item.url.absoluteString)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                if case .failed(let error) = item.status {
                                    Text(error).font(.caption2).foregroundStyle(.red)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }
    #endif

    // MARK: - URL Input Section

    @ViewBuilder
    private var urlInputSection: some View {
        Section {
            #if os(tvOS)
            // tvOS doesn't have TextEditor, use TextField for single URL
            TextField(String(localized: "openLink.urlPlaceholder"), text: $urlText)
                .textContentType(.URL)
                .focused($isTextEditorFocused)
                .disabled(isExtracting)
            #else
            TextEditor(text: $urlText)
                .frame(minHeight: 100, maxHeight: 200)
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                .autocapitalization(.none)
                .keyboardType(.URL)
                #endif
                .focused($isTextEditorFocused)
                .disabled(isExtracting)
            #endif

            #if !os(tvOS)
            // URL count indicator (not shown on tvOS since it only supports single URL)
            HStack {
                if isTooManyURLs {
                    Label(
                        String(localized: "openLink.tooManyUrls \(Self.maxURLs)"),
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                } else if urlCount > 0 {
                    Text(String(localized: "openLink.urlCount \(urlCount)"))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
            }

            // Clipboard paste button (not available on tvOS)
            if !clipboardURLs.isEmpty, !isExtracting {
                let clipboardText = clipboardURLs.map(\.absoluteString).joined(separator: "\n")
                if clipboardText != urlText {
                    Button {
                        urlText = clipboardText
                    } label: {
                        HStack {
                            Image(systemName: "doc.on.clipboard")
                            VStack(alignment: .leading) {
                                if clipboardURLs.count > 1 {
                                    Text(String(localized: "openLink.pasteMultiple \(clipboardURLs.count)"))
                                        .font(.subheadline)
                                } else {
                                    Text(String(localized: "openLink.pasteClipboard"))
                                        .font(.subheadline)
                                }
                                Text(clipboardURLs.first?.host ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }
                }
            }
            #endif
        } footer: {
            Text(supportedSitesHint)
        }
    }

    /// Dynamic hint text based on enabled backend instances.
    private var supportedSitesHint: String {
        guard let instancesManager = appEnvironment?.instancesManager else {
            return String(localized: "openLink.hint.noInstances")
        }

        let hasEnabledYatteeServer = !instancesManager.enabledYatteeServerInstances.isEmpty
        let hasEnabledInvidiousPiped = instancesManager.enabledInstances.contains {
            $0.type == .invidious || $0.type == .piped
        }

        if hasEnabledYatteeServer {
            return String(localized: "openLink.hint.yatteeServer")
        } else if hasEnabledInvidiousPiped {
            return String(localized: "openLink.hint.youtubeOnly")
        } else {
            return String(localized: "openLink.hint.noInstances")
        }
    }

    // MARK: - Extraction Results Section

    @ViewBuilder
    private var extractionResultsSection: some View {
        if !extractedItems.isEmpty {
            Section {
                ForEach(extractedItems) { item in
                    HStack(spacing: 12) {
                        // Status indicator
                        Group {
                            switch item.status {
                            case .pending:
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            case .extracting:
                                ProgressView()
                                    .controlSize(.small)
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failed:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                        .frame(width: 20)

                        // URL info
                        VStack(alignment: .leading, spacing: 2) {
                            if let video = item.video {
                                Text(video.title)
                                    .lineLimit(1)
                                Text(item.displayHost)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                // No video extracted - show full URL (useful for failures)
                                Text(item.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            if case .failed(let error) = item.status {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }

                        Spacer()
                    }
                }
            } header: {
                if isExtracting {
                    let processed = extractedItems.filter { item in
                        switch item.status {
                        case .pending: return false
                        default: return true
                        }
                    }.count
                    Text(String(localized: "openLink.extractingProgress \(processed) \(extractedItems.count)"))
                } else {
                    Text(String(localized: "openLink.results"))
                }
            }
        }
    }

    // MARK: - Action Buttons Section

    @ViewBuilder
    private var actionButtonsSection: some View {
        Section {
            if isExtracting {
                HStack {
                    ProgressView()
                    Text(String(localized: "openLink.extracting"))
                        .foregroundStyle(.secondary)
                }
            } else {
                // Load: show the link's video, playlist or channel screen,
                // or several links as mixed results
                Button {
                    isTextEditorFocused = false
                    Task { await loadURLs() }
                } label: {
                    Label(loadButtonTitle, systemImage: "arrow.right.circle")
                        .fontWeight(.semibold)
                }
                .disabled(!isValidInput)

                if allLinksAreVideos {
                    // Play shortcut
                    Button {
                        isTextEditorFocused = false
                        Task { await openAllURLs() }
                    } label: {
                        Label(
                            isMultipleURLs
                                ? String(localized: "openLink.openAll")
                                : String(localized: "openLink.open"),
                            systemImage: "play.fill"
                        )
                    }
                    .disabled(!isValidInput)

                    #if !os(tvOS)
                    // Download shortcut
                    Button {
                        isTextEditorFocused = false
                        Task { await downloadAllURLs() }
                    } label: {
                        Label(
                            isMultipleURLs
                                ? String(localized: "openLink.downloadAll")
                                : String(localized: "openLink.download"),
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .disabled(!isValidInput)
                    #endif
                }
            }
        }
    }

    // MARK: - Yattee Server Warning Section

    @ViewBuilder
    private var yatteeServerWarningSection: some View {
        if !hasYatteeServer && hasExternalURLs && !isExtracting {
            Section {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(String(localized: "openLink.yatteeServerNotConfigured"))
                        .font(.subheadline)
                }
                Text(String(localized: "openLink.yatteeServerMessage"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var hasYatteeServer: Bool {
        appEnvironment?.instancesManager.yatteeServerInstance != nil
    }

    /// Parse URLs from input text, one per line.
    private var parsedURLs: [URL] {
        urlText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "http" || scheme == "https") && url.host != nil
            }
            .prefix(Self.maxURLs)
            .map { $0 }
    }

    private var urlCount: Int { parsedURLs.count }
    private var isValidInput: Bool { !parsedURLs.isEmpty }
    private var isMultipleURLs: Bool { urlCount > 1 }

    private var isTooManyURLs: Bool {
        urlText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count > Self.maxURLs
    }

    /// Whether any of the parsed URLs are external (non-YouTube/PeerTube).
    private var hasExternalURLs: Bool {
        let router = URLRouter()
        return parsedURLs.contains { url in
            if let destination = router.route(url) {
                if case .externalVideo = destination { return true }
                return false
            }
            // YouTube pages that route nowhere are unsupported, not external
            return !router.isYouTubeHost(url.host)
        }
    }

    /// Whether every parsed link is a video, so Play and Download apply.
    /// Playlists and channels can only be loaded.
    private var allLinksAreVideos: Bool {
        let router = URLRouter()
        return parsedURLs.allSatisfy { url in
            switch router.route(url) {
            case .video, .externalVideo, .directMedia: return true
            case nil: return !router.isYouTubeHost(url.host)
            default: return false
            }
        }
    }

    // MARK: - Clipboard

    private func checkClipboard() {
        clipboardURLs = []

        #if os(iOS)
        if let string = UIPasteboard.general.string {
            clipboardURLs = parseURLsFromString(string)
        }
        #elseif os(macOS)
        if let string = NSPasteboard.general.string(forType: .string) {
            clipboardURLs = parseURLsFromString(string)
        }
        #endif
    }

    private func parseURLsFromString(_ string: String) -> [URL] {
        string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { URL(string: $0) }
            .filter { url in
                guard let scheme = url.scheme?.lowercased() else { return false }
                return (scheme == "http" || scheme == "https") && url.host != nil
            }
            .prefix(Self.maxURLs)
            .map { $0 }
    }

    // MARK: - Load Action

    private var loadButtonTitle: String {
        isMultipleURLs ? String(localized: "openLink.loadAll") : String(localized: "openLink.load")
    }

    /// Shows a single link's screen, or several links on the Opened Links
    /// page, which resolves them itself.
    private func loadURLs() async {
        let urls = parsedURLs
        guard let appEnvironment, !urls.isEmpty else { return }
        // A watch link inside a playlist shows both, like several links
        if urls.count > 1 || URLRouter().youTubePlaylistContext(urls[0]) != nil {
            extractedItems = []
            dismissIfRequested()
            appEnvironment.navigationCoordinator.navigateToOpenedLink(.openedLinks(urls))
        } else {
            await loadURL()
        }
    }

    /// Resolves the single link and shows its screen: a video's details page,
    /// or the playlist / channel screen. Errors stay in the form.
    private func loadURL() async {
        guard let url = parsedURLs.first, !isMultipleURLs, let appEnvironment else { return }

        isExtracting = true
        hasErrors = false
        extractedItems = [ExtractedItem(url: url, status: .extracting)]

        do {
            let destination = try await LinkVideoResolver(appEnvironment: appEnvironment).resolveDestination(url)
            if case .video(.loaded(let video), _) = destination {
                extractedItems[0].video = video
            }
            extractedItems[0].status = .success
            isExtracting = false
            dismissIfRequested()
            appEnvironment.navigationCoordinator.navigateToOpenedLink(destination)
        } catch {
            extractedItems[0].status = .failed(error.localizedDescription)
            hasErrors = true
            isExtracting = false
        }
    }

    // MARK: - Open (Play) Action

    private func openAllURLs() async {
        let urls = parsedURLs
        guard !urls.isEmpty, let appEnvironment else { return }

        isExtracting = true
        hasErrors = false
        extractedItems = urls.map { ExtractedItem(url: $0) }

        var successCount = 0
        var failedCount = 0
        var firstVideoPlayed = false

        for (index, url) in urls.enumerated() {
            extractedItems[index].status = .extracting

            do {
                let (video, streams, _, _) = try await LinkVideoResolver(appEnvironment: appEnvironment).resolve(url)
                extractedItems[index].status = .success
                extractedItems[index].video = video
                extractedItems[index].streams = streams
                successCount += 1

                if !firstVideoPlayed {
                    // Play first video - this expands player
                    await playVideo(video, sourceURL: url, appEnvironment: appEnvironment)
                    firstVideoPlayed = true
                } else {
                    // Add to queue
                    appEnvironment.queueManager.addToQueue(video, queueSource: .manual)
                }
            } catch {
                extractedItems[index].status = .failed(error.localizedDescription)
                failedCount += 1
                hasErrors = true
            }
        }

        isExtracting = false

        // Show completion toast and handle dismissal
        if failedCount == 0 {
            if successCount > 1 {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "openLink.queuedSuccess.title"),
                    subtitle: String(localized: "openLink.queuedSuccess.subtitle \(successCount)")
                )
            }
            dismissIfRequested()
        } else if successCount > 0 {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.queuedPartial.title"),
                subtitle: String(localized: "openLink.queuedPartial.subtitle \(successCount) \(failedCount)")
            )
            // Keep sheet open so user can see errors
        } else {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.allFailed.title"),
                subtitle: String(localized: "openLink.allFailed.subtitle \(failedCount)")
            )
            // Keep sheet open
        }
    }

    private func playVideo(_ video: Video, sourceURL: URL, appEnvironment: AppEnvironment) async {
        // Don't pass a specific stream - let the player's selectStreamAndBackend
        // choose the best video+audio combination. Using streams.first would
        // incorrectly select audio-only streams for sites like Bilibili.
        let router = URLRouter()
        let startTime = router.parseTimestamp(router.unwrapped(sourceURL))
        // A watch link inside a playlist queues the playlist around it.
        // Awaited, so later links queue after the playlist instead of being
        // cleared by it.
        await LinkVideoResolver(appEnvironment: appEnvironment).play(video, from: sourceURL, startTime: startTime)
    }

    // MARK: - Download Action

    #if !os(tvOS)
    private func downloadAllURLs() async {
        let urls = parsedURLs
        guard !urls.isEmpty, let appEnvironment else { return }

        isExtracting = true
        hasErrors = false
        extractedItems = urls.map { ExtractedItem(url: $0) }

        let downloadSettings = appEnvironment.downloadSettings
        var successCount = 0
        var failedCount = 0

        for (index, url) in urls.enumerated() {
            extractedItems[index].status = .extracting

            do {
                let (video, streams, captions, storyboards) = try await LinkVideoResolver(appEnvironment: appEnvironment).resolve(url)
                extractedItems[index].status = .success
                extractedItems[index].video = video
                extractedItems[index].streams = streams
                extractedItems[index].captions = captions
                extractedItems[index].storyboards = storyboards
                successCount += 1

                // If auto-download is configured, enqueue immediately
                if downloadSettings.preferredDownloadQuality != .ask {
                    try await LinkVideoResolver(appEnvironment: appEnvironment).enqueueDownload(
                        video: video,
                        streams: streams,
                        captions: captions,
                        storyboards: storyboards,
                        quality: downloadSettings.preferredDownloadQuality,
                        includeSubtitles: downloadSettings.includeSubtitlesInAutoDownload
                    )
                }
            } catch {
                extractedItems[index].status = .failed(error.localizedDescription)
                failedCount += 1
                hasErrors = true
            }
        }

        isExtracting = false

        // Handle completion based on download mode
        if downloadSettings.preferredDownloadQuality == .ask {
            // Show quality picker for all extracted videos
            pendingDownloadItems = extractedItems.filter { $0.video != nil }
            if !pendingDownloadItems.isEmpty {
                showingDownloadSheet = true
            } else if failedCount > 0 {
                appEnvironment.toastManager.show(
                    category: .error,
                    title: String(localized: "openLink.allFailed.title"),
                    subtitle: String(localized: "openLink.allFailed.subtitle \(failedCount)")
                )
            }
        } else {
            // Auto-download mode - show completion toast
            if failedCount == 0 {
                if successCount >= 2 {
                    appEnvironment.toastManager.showSuccess(
                        String(localized: "openLink.downloadQueued.title"),
                        subtitle: String(localized: "openLink.downloadQueued.subtitle \(successCount)")
                    )
                }
                dismissIfRequested()
            } else if successCount > 0 {
                appEnvironment.toastManager.show(
                    category: .error,
                    title: String(localized: "openLink.downloadPartial.title"),
                    subtitle: String(localized: "openLink.downloadPartial.subtitle \(successCount) \(failedCount)")
                )
                // Keep sheet open
            } else {
                appEnvironment.toastManager.show(
                    category: .error,
                    title: String(localized: "openLink.allFailed.title"),
                    subtitle: String(localized: "openLink.allFailed.subtitle \(failedCount)")
                )
                // Keep sheet open
            }
        }
    }

    /// Downloads pending items after user selects quality.
    private func downloadPendingItems(quality: DownloadQuality, includeSubtitles: Bool) async {
        guard let appEnvironment else { return }

        var successCount = 0
        var failedCount = 0

        for item in pendingDownloadItems {
            guard let video = item.video else { continue }

            do {
                try await LinkVideoResolver(appEnvironment: appEnvironment).enqueueDownload(
                    video: video,
                    streams: item.streams,
                    captions: item.captions,
                    storyboards: item.storyboards,
                    quality: quality,
                    includeSubtitles: includeSubtitles
                )
                successCount += 1
            } catch {
                failedCount += 1
            }
        }

        pendingDownloadItems = []

        // Show completion toast
        if failedCount == 0 {
            if successCount >= 2 {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "openLink.downloadQueued.title"),
                    subtitle: String(localized: "openLink.downloadQueued.subtitle \(successCount)")
                )
            }
            if !hasErrors {
                dismissIfRequested()
            }
        } else {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "openLink.downloadPartial.title"),
                subtitle: String(localized: "openLink.downloadPartial.subtitle \(successCount) \(failedCount)")
            )
        }
    }

    #endif
}

// MARK: - Previews

#Preview {
    OpenLinkSheet()
}

#Preview("With URL") {
    OpenLinkSheet(prefilledURL: URL(string: "https://vimeo.com/123456789"))
}

#Preview("Multiple URLs") {
    OpenLinkSheet(prefilledURL: URL(string: "https://youtube.com/watch?v=abc123"))
}
