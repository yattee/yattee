//
//  CheckForUpdatesMenuItem.swift
//  Yattee
//
//  "Check for Updates…" menu item shown in the macOS app menu for
//  Developer ID builds. Wired to the Sparkle-backed `AppUpdater`.
//
//  Compiled in only when the `SPARKLE` Swift flag is set (i.e. the
//  `Release-DeveloperID` configuration). See AGENTS.md.
//

#if SPARKLE && os(macOS)

import SwiftUI

struct CheckForUpdatesMenuItem: View {
    @State private var updater = AppUpdater.shared

    var body: some View {
        Button(String(localized: "menu.app.checkForUpdates")) {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

#endif
