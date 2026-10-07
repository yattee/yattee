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
    /// Play now / queue choices for a tapped video while something is playing.
    case queueAction(Video, queueSource: QueueSource? = nil)
    /// Details of a playback or loading error.
    case errorDetails(String)
    /// Open a link, optionally prefilled.
    case openLink(URL?)
    /// Continue / start over for a partially watched video.
    case resumeAction(Video, resumeTime: TimeInterval, onContinue: () -> Void, onStartOver: () -> Void)
    /// Asks before a URL scheme action changes saved state.
    case linkActionConfirmation(LinkActionConfirmation)
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
        case .errorDetails:
            return "errorDetails"
        case .openLink:
            return "openLink"
        case .queueAction(let video, _):
            return "queueAction-\(video.id.id)"
        case .resumeAction(let video, _, _, _):
            return "resumeAction-\(video.id.id)"
        case .linkActionConfirmation(let confirmation):
            return "linkActionConfirmation-\(confirmation.id)"
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

// MARK: - Toasts

/// The toast overlay level of a presented sheet.
struct SheetToastLevel {
    let scope: ToastScope
    let depth: Int
}

extension EnvironmentValues {
    @Entry var sheetToastLevel = SheetToastLevel(scope: .main, depth: 0)
}

// MARK: - Host

private struct AppSheetHost: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Whether this host presents global requests (`PresentationRouter.request`).
    let isTopLevel: Bool
    /// Whether external navigation dismisses this host's sheet. Only the main
    /// window's root host: the expanded player keeps its own sheets.
    let dismissesOnExternalNavigation: Bool

    /// The toast scope of the window this host is in; nil inherits it.
    let toastScope: ToastScope?

    @Environment(\.sheetToastLevel) private var parentToastLevel
    @State private var sheet: AppSheet?

    /// Where this host's sheets show toasts: the window's scope, one level
    /// deeper than the content they cover.
    private var sheetToastLevel: SheetToastLevel {
        SheetToastLevel(scope: toastScope ?? parentToastLevel.scope, depth: toastScope == nil ? parentToastLevel.depth + 1 : 1)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.presentAppSheet, PresentAppSheetAction { sheet = $0 })
            .sheet(item: $sheet) { sheet in
                sheetContent(for: sheet)
                    .sheetToastOverlay(scope: sheetToastLevel.scope, depth: sheetToastLevel.depth)
                    .environment(\.sheetToastLevel, sheetToastLevel)
            }
            // Declared before the request observer so a deep link that both
            // dismisses and presents ends with its own sheet up.
            .onChange(of: dismissGeneration) { _, _ in
                sheet = nil
            }
            .onChange(of: pendingRequestID, initial: true) { _, _ in
                takePendingRequest()
            }
    }

    private var dismissGeneration: Int? {
        dismissesOnExternalNavigation ? appEnvironment?.navigationCoordinator.dismissPresentationsGeneration : nil
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
            case .errorDetails(let message):
                ErrorDetailsSheet(errorMessage: message)
            case .openLink(let url):
                OpenLinkSheet(prefilledURL: url)
            case .queueAction(let video, let queueSource):
                QueueActionSheet(video: video, queueSource: queueSource)
            case .resumeAction(let video, let resumeTime, let onContinue, let onStartOver):
                ResumeActionSheet(video: video, resumeTime: resumeTime, onContinue: onContinue, onStartOver: onStartOver)
            case .linkActionConfirmation(let confirmation):
                LinkActionConfirmationSheet(confirmation: confirmation)
            #if !os(tvOS)
            case .downloadOptions(let video, let streams, let captions, let dislikeCount):
                DownloadQualitySheet(video: video, streams: streams, captions: captions, dislikeCount: dislikeCount)
            #endif
            }
        }
        // The next level: sheets opened from inside this one. It goes away
        // with this sheet, so it needn't observe external navigation itself.
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
    /// - Parameter dismissesOnExternalNavigation: true for the main window's
    ///   root host, whose sheet external navigation (notification, deep link,
    ///   Handoff) dismisses.
    /// - Parameter toastScope: the toast scope of the window the host is in;
    ///   nil for hosts inside sheets, which inherit it.
    func appSheetHost(isTopLevel: Bool, dismissesOnExternalNavigation: Bool = false, toastScope: ToastScope? = nil) -> some View {
        modifier(AppSheetHost(
            isTopLevel: isTopLevel,
            dismissesOnExternalNavigation: dismissesOnExternalNavigation,
            toastScope: toastScope
        ))
    }

    /// Dismisses a screen's own sheet when navigation arrives from outside the
    /// app, so it doesn't stay up over the screen the navigation moved to.
    func dismissesOnExternalNavigation(_ isPresented: Binding<Bool>) -> some View {
        modifier(ExternalNavigationDismissal(isPresented: isPresented))
    }
}

private struct ExternalNavigationDismissal: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: appEnvironment?.navigationCoordinator.dismissPresentationsGeneration) { _, _ in
                isPresented = false
            }
    }
}
