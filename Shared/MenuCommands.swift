import Foundation
import SwiftUI

struct MenuCommands: Commands {
    @Binding var model: MenuModel

    var body: some Commands {
        navigationMenu
        playbackMenu
    }

    private var navigationMenu: some Commands {
        CommandMenu("Navigation") {
            Button("Favorites") {
                model.navigation?.tabSelection = .favorites
            }
            .keyboardShortcut("1")

            Button("Subscriptions") {
                model.navigation?.tabSelection = .subscriptions
            }
            .disabled(!(model.accounts?.app.supportsSubscriptions ?? true))
            .keyboardShortcut("2")

            Button("Popular") {
                model.navigation?.tabSelection = .popular
            }
            .disabled(!(model.accounts?.app.supportsPopular ?? true))
            .keyboardShortcut("3")

            Button("Trending") {
                model.navigation?.tabSelection = .trending
            }
            .keyboardShortcut("4")

            Button("Search") {
                model.navigation?.tabSelection = .search
            }
            .keyboardShortcut("f")
        }
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

            Button((model.player?.presentingPlayer ?? true) ? "Hide Player" : "Show Player") {
                model.player?.togglePlayer()
            }
            .keyboardShortcut("o")
        }
    }
}
