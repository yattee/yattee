//
//  NavigationCommands.swift
//  Yattee
//
//  Menu bar commands for tab navigation.
//

import SwiftUI

#if !os(tvOS)
/// Navigation-related menu bar commands.
/// Works on both macOS and iPadOS 26+.
struct NavigationCommands: Commands {
    let appEnvironment: AppEnvironment

    private var navigationCoordinator: NavigationCoordinator {
        appEnvironment.navigationCoordinator
    }

    private var settingsManager: SettingsManager {
        appEnvironment.settingsManager
    }

    private var visibleItems: [SidebarMainItem] {
        settingsManager.visibleSidebarMainItems()
    }

    var body: some Commands {
        CommandMenu(String(localized: "menu.navigation")) {
            // Home is always visible (required)
            homeButton
            if visibleItems.contains(.subscriptions) {
                subscriptionsButton
            }
            Divider()
            if visibleItems.contains(.bookmarks) {
                bookmarksButton
            }
            if visibleItems.contains(.history) {
                historyButton
            }
            if visibleItems.contains(.downloads) {
                downloadsButton
            }
            Divider()
            if visibleItems.contains(.channels) {
                channelsButton
            }
            if visibleItems.contains(.sources) {
                sourcesButton
            }
            Divider()
            // Search is always visible (required)
            searchButton
            if visibleItems.contains(.settings) {
                settingsButton
            }
        }
    }

    private var homeButton: some View {
        Button {
            navigationCoordinator.selectedTab = .home
        } label: {
            Text(String(localized: "menu.navigation.home"))
        }
        .keyboardShortcut("1", modifiers: [.command])
    }

    private var subscriptionsButton: some View {
        Button {
            navigationCoordinator.selectedTab = .subscriptions
        } label: {
            Text(String(localized: "menu.navigation.subscriptions"))
        }
        .keyboardShortcut("2", modifiers: [.command])
    }

    private var searchButton: some View {
        Button {
            navigationCoordinator.selectedTab = .search
        } label: {
            Text(String(localized: "menu.navigation.search"))
        }
        .keyboardShortcut("f", modifiers: [.command])
    }

    private var bookmarksButton: some View {
        Button {
            navigationCoordinator.selectedSidebarItem = .bookmarks
        } label: {
            Text(String(localized: "menu.navigation.bookmarks"))
        }
        .keyboardShortcut("3", modifiers: [.command])
    }

    private var historyButton: some View {
        Button {
            navigationCoordinator.selectedSidebarItem = .history
        } label: {
            Text(String(localized: "menu.navigation.history"))
        }
        .keyboardShortcut("4", modifiers: [.command])
    }

    private var downloadsButton: some View {
        Button {
            navigationCoordinator.selectedSidebarItem = .downloads
        } label: {
            Text(String(localized: "menu.navigation.downloads"))
        }
        .keyboardShortcut("5", modifiers: [.command])
    }

    private var channelsButton: some View {
        Button {
            navigationCoordinator.selectedSidebarItem = .manageChannels
        } label: {
            Text(String(localized: "menu.navigation.channels"))
        }
        .keyboardShortcut("6", modifiers: [.command])
    }

    private var sourcesButton: some View {
        Button {
            navigationCoordinator.selectedSidebarItem = .sources
        } label: {
            Text(String(localized: "menu.navigation.sources"))
        }
        .keyboardShortcut("7", modifiers: [.command])
    }

    private var settingsButton: some View {
        Button {
            navigationCoordinator.selectedSidebarItem = .settings
        } label: {
            Text(String(localized: "menu.navigation.settings"))
        }
        .keyboardShortcut("9", modifiers: [.command])
    }
}
#endif
