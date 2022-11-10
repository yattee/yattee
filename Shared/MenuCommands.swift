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
            Button("Open Videos...") { model.navigation?.presentingOpenVideos = true }
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
            .disabled(!(model.accounts?.app.supportsPopular ?? false))
            .keyboardShortcut("3")

            Button("Trending") {
                setTabSelection(.trending)
            }
            .keyboardShortcut("4")

            Button("Search") {
                setTabSelection(.search)
            }
            .keyboardShortcut("f")

            Divider()
        }
    }

    private func setTabSelection(_ tabSelection: NavigationModel.TabSelection) {
        guard let navigation = model.navigation else {
            return
        }

        navigation.sidebarSectionChanged.toggle()
        navigation.tabSelection = tabSelection
    }

    private var subscriptionsDisabled: Bool {
        !(
            (model.accounts?.app.supportsSubscriptions ?? false) && model.accounts?.signedIn ?? false
        )
    }

    private var playbackMenu: some Commands {
        CommandMenu("Playback") {
            Button((model.player?.isPlaying ?? true) ? "Pause" : "Play") {
                model.player?.togglePlay()
            }
            .disabled(model.player?.currentItem.isNil ?? true)
            .keyboardShortcut("p")

            Button("Play Next") {
                model.player?.advanceToNextItem()
            }
            .disabled(model.player?.queue.isEmpty ?? true)
            .keyboardShortcut("s")

            Button(togglePlayerLabel) {
                model.player?.togglePlayer()
            }
            .keyboardShortcut("o")
        }
    }

    private var togglePlayerLabel: String {
        #if os(macOS)
            "Show Player"
        #else
            (model.player?.presentingPlayer ?? true) ? "Hide Player" : "Show Player"
        #endif
    }
}
