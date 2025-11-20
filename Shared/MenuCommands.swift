import Foundation
import SwiftUI

struct MenuCommands: Commands {
    @Binding var model: MenuModel

    var body: some Commands {
        openVideosMenu
        navigationMenu
        playbackMenu
    }

    private var openVideosMenu: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Videos...") { NavigationModel.shared.presentingOpenVideos = true }
                .keyboardShortcut("t")
        }
    }

    private var navigationMenu: some Commands {
        CommandGroup(before: .windowSize) {
            Button("Home") {
                setTabSelection(.home)
            }
            .keyboardShortcut("1")

            Button("Subscriptions") {
                setTabSelection(.subscriptions)
            }
            .disabled(subscriptionsDisabled)
            .keyboardShortcut("2")

            Button("Popular") {
                setTabSelection(.popular)
            }
            .disabled(!AccountsModel.shared.app.supportsPopular)
            .keyboardShortcut("3")

            Button("Trending") {
                setTabSelection(.trending)
            }
            .disabled(!FeatureFlags.trendingEnabled)
            .keyboardShortcut("4")

            Button("Search") {
                setTabSelection(.search)
            }
            .keyboardShortcut("f")

            Divider()
        }
    }

    private func setTabSelection(_ tabSelection: NavigationModel.TabSelection) {
        NavigationModel.shared.sidebarSectionChanged.toggle()
        NavigationModel.shared.tabSelection = tabSelection
    }

    private var subscriptionsDisabled: Bool {
        !(AccountsModel.shared.app.supportsSubscriptions && AccountsModel.shared.signedIn)
    }

    private var playbackMenu: some Commands {
        CommandMenu("Playback") {
            Button((PlayerModel.shared.isPlaying) ? "Pause" : "Play") {
                PlayerModel.shared.togglePlay()
            }
            .disabled(PlayerModel.shared.currentItem.isNil)
            .keyboardShortcut("p")

            Button("Play Next") {
                PlayerModel.shared.advanceToNextItem()
            }
            .disabled(PlayerModel.shared.queue.isEmpty)
            .keyboardShortcut("s")

            Button(togglePlayerLabel) {
                PlayerModel.shared.togglePlayer()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }

    private var togglePlayerLabel: String {
        #if os(macOS)
            "Show Player"
        #else
            PlayerModel.shared.presentingPlayer ? "Hide Player" : "Show Player"
        #endif
    }
}
