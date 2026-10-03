//
//  PresentationRouter.swift
//  Yattee
//
//  Shared sheets, declared once per host instead of once per screen or row.
//
//  Views present through `@Environment(\.presentAppSheet)`, which reaches the
//  nearest `.appSheetHost()` above them: the app root, the expanded player,
//  or a sheet that is itself presented by a host (each presented sheet hosts
//  the next level). Code outside the view tree uses `PresentationRouter.request`,
//  which the top-most host (the player when expanded, the root otherwise)
//  picks up.
//

import SwiftUI

/// Sheets presented through `.appSheetHost()`.
enum AppSheet: Identifiable {
    /// Queue of the current player. `halfHeight` opens at the medium detent.
    case queue(halfHeight: Bool = false)
    /// Add a video to a playlist. `halfHeight` opens at the medium detent.
    case addToPlaylist(Video, halfHeight: Bool = false)
    #if !os(tvOS)
    /// Download quality picker. Streams and captions already loaded by the
    /// caller (the player) skip the sheet's own fetch.
    case downloadOptions(Video, streams: [Stream] = [], captions: [Caption] = [], dislikeCount: Int? = nil)
    #endif

    var id: String {
        switch self {
        case .queue:
            return "queue"
        case .addToPlaylist(let video, _):
            return "addToPlaylist-\(video.id.id)"
        #if !os(tvOS)
        case .downloadOptions(let video, _, _, _):
            return "downloadOptions-\(video.id.id)"
        #endif
        }
    }
}

@Observable
@MainActor
final class PresentationRouter {
    /// A sheet requested from outside the view tree. The top-most host moves
    /// it into its own state and clears this.
    var request: AppSheet?

    func present(_ sheet: AppSheet) {
        request = sheet
    }
}

// MARK: - Environment

/// Presents an `AppSheet` from the nearest host.
struct PresentAppSheetAction {
    fileprivate let handler: @MainActor (AppSheet) -> Void

    @MainActor
    func callAsFunction(_ sheet: AppSheet) {
        handler(sheet)
    }
}

extension EnvironmentValues {
    /// Outside any host this falls back to the global request, which the
    /// top-most host presents.
    @Entry var presentAppSheet = PresentAppSheetAction { sheet in
        AppEnvironment.shared.navigationCoordinator.presenter.present(sheet)
    }
}

// MARK: - Host

private struct AppSheetHost: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Whether this host presents global requests (`PresentationRouter.request`).
    let isTopLevel: Bool

    @State private var sheet: AppSheet?

    func body(content: Content) -> some View {
        content
            .environment(\.presentAppSheet, PresentAppSheetAction { sheet = $0 })
            #if os(tvOS)
            .fullScreenCover(item: $sheet) { sheet in
                sheetContent(for: sheet)
                    .tvFullScreenCoverBackground()
            }
            #else
            .sheet(item: $sheet) { sheet in
                sheetContent(for: sheet)
            }
            #endif
            .onChange(of: pendingRequestID, initial: true) { _, _ in
                takePendingRequest()
            }
    }

    private var pendingRequestID: String? {
        isTopLevel ? appEnvironment?.navigationCoordinator.presenter.request?.id : nil
    }

    private func takePendingRequest() {
        guard isTopLevel, let presenter = appEnvironment?.navigationCoordinator.presenter,
              let request = presenter.request else { return }
        presenter.request = nil
        sheet = request
    }

    @ViewBuilder
    private func sheetContent(for sheet: AppSheet) -> some View {
        Group {
            switch sheet {
            case .queue(let halfHeight):
                QueueManagementSheet()
                    .halfHeightDetents(halfHeight)
            case .addToPlaylist(let video, let halfHeight):
                PlaylistSelectorSheet(video: video)
                    .halfHeightDetents(halfHeight)
            #if !os(tvOS)
            case .downloadOptions(let video, let streams, let captions, let dislikeCount):
                DownloadQualitySheet(video: video, streams: streams, captions: captions, dislikeCount: dislikeCount)
            #endif
            }
        }
        // The next level: sheets opened from inside this one.
        .appSheetHost(isTopLevel: false)
        .optionalAppEnvironment(appEnvironment)
    }
}

private extension View {
    @ViewBuilder
    func halfHeightDetents(_ halfHeight: Bool) -> some View {
        if halfHeight {
            presentationDetents([.medium, .large])
        } else {
            self
        }
    }

    @ViewBuilder
    func optionalAppEnvironment(_ appEnvironment: AppEnvironment?) -> some View {
        if let appEnvironment {
            self.appEnvironment(appEnvironment)
        } else {
            self
        }
    }
}

extension View {
    /// Hosts `AppSheet`s for the content below it.
    ///
    /// - Parameter isTopLevel: true for the hosts that present global requests:
    ///   the app root while the player is collapsed, the expanded player while
    ///   it is up.
    func appSheetHost(isTopLevel: Bool) -> some View {
        modifier(AppSheetHost(isTopLevel: isTopLevel))
    }
}
