//
//  ResolvedLinkPromptsModifier.swift
//  Yattee
//
//  Hosts the two confirmation dialogs used when a tapped description/comment
//  link needs user approval:
//
//  - `resolvedShortLinkPrompt`  — a bit.ly/t.co/… shortener resolved to a URL
//    that isn't confidently a playable video.
//  - `ambiguousExternalLinkPrompt` — a non-shortener URL that only matches the
//    loose `.externalVideo` yt-dlp fallback (e.g. an arbitrary webpage).
//
//  The state lives on `NavigationCoordinator` so both the root app view and
//  `ExpandedPlayerSheet` can host the dialogs. Only whichever host is currently
//  on top presents the dialog (`shouldHost`), so the dialog is visible whether
//  the expanded player is covering the main view or not — matching the
//  `descriptionLinkQueueSheetVideo` pattern.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ResolvedLinkPromptsModifier: ViewModifier {
    /// Whether this host should actually present the dialogs right now. Used
    /// so YatteeApp (root) only presents when the expanded player isn't up,
    /// and ExpandedPlayerSheet only presents when it *is* up.
    let shouldHost: Bool
    /// Passed in explicitly (rather than read from `@Environment`) because
    /// YatteeApp applies this modifier *outside* its `.appEnvironment(…)`
    /// injection, where the environment value isn't set yet. Nil-safe so
    /// ExpandedPlayerSheet (which holds an optional) can pass through.
    let appEnvironment: AppEnvironment?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                String(localized: "alert.resolvedShortLink.title"),
                isPresented: shortLinkBinding,
                titleVisibility: .visible,
                presenting: shouldHost ? appEnvironment?.navigationCoordinator.resolvedShortLinkPrompt : nil
            ) { url in
                Button(String(localized: "alert.resolvedShortLink.openInYattee")) {
                    NotificationCenter.default.post(name: .openDescriptionLink, object: url)
                }
                Button(String(localized: "alert.resolvedShortLink.openInBrowser")) {
                    openInSystemBrowser(url)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: { url in
                Text(String(localized: "alert.resolvedShortLink.message \(url.absoluteString)"))
            }
            .confirmationDialog(
                String(localized: "alert.ambiguousLink.title"),
                isPresented: ambiguousBinding,
                titleVisibility: .visible,
                presenting: shouldHost ? appEnvironment?.navigationCoordinator.ambiguousExternalLinkPrompt : nil
            ) { url in
                Button(String(localized: "alert.ambiguousLink.tryInYattee")) {
                    NotificationCenter.default.post(name: .openDescriptionLink, object: url)
                }
                Button(String(localized: "alert.ambiguousLink.openInBrowser")) {
                    openInSystemBrowser(url)
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            } message: { url in
                Text(String(localized: "alert.ambiguousLink.message \(url.absoluteString)"))
            }
    }

    private var shortLinkBinding: Binding<Bool> {
        Binding(
            get: { shouldHost && appEnvironment?.navigationCoordinator.resolvedShortLinkPrompt != nil },
            set: { presented in
                if !presented {
                    appEnvironment?.navigationCoordinator.resolvedShortLinkPrompt = nil
                }
            }
        )
    }

    private var ambiguousBinding: Binding<Bool> {
        Binding(
            get: { shouldHost && appEnvironment?.navigationCoordinator.ambiguousExternalLinkPrompt != nil },
            set: { presented in
                if !presented {
                    appEnvironment?.navigationCoordinator.ambiguousExternalLinkPrompt = nil
                }
            }
        )
    }

    @MainActor
    private func openInSystemBrowser(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #elseif os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }
}

extension View {
    /// Apply at both root (when `!isPlayerExpanded`) and expanded-player level
    /// (when `isPlayerExpanded`) to keep the confirmation dialogs visible above
    /// whichever layer is showing. `appEnvironment` must be passed in rather
    /// than read from the environment because the root call site applies this
    /// modifier outside the `.appEnvironment(…)` injection point.
    func resolvedLinkPrompts(shouldHost: Bool, appEnvironment: AppEnvironment?) -> some View {
        modifier(ResolvedLinkPromptsModifier(shouldHost: shouldHost, appEnvironment: appEnvironment))
    }
}
