import Foundation
import SwiftUI

final class NavigationState: ObservableObject {
    @Published var tabSelection: TabSelection = .subscriptions

    @Published var showingChannel = false
    @Published var channel: Channel?

    @Published var showingVideoDetails = false
    @Published var showingVideo = false
    @Published var video: Video?

    @Published var returnToDetails = false

    func openChannel(_ channel: Channel) {
        returnToDetails = false
        self.channel = channel
        showingChannel = true
    }

    func closeChannel() {
        showingChannel = false
        channel = nil
    }

    func openVideoDetails(_ video: Video) {
        self.video = video
        showingVideoDetails = true
    }

    func closeVideoDetails() {
        showingVideoDetails = false
        video = nil
    }

    func playVideo(_ video: Video) {
        self.video = video
        showingVideo = true
    }

    func showVideoDetailsIfNeeded() {
        showingVideoDetails = returnToDetails
        returnToDetails = false
    }

    var tabSelectionOptionalBinding: Binding<TabSelection?> {
        Binding<TabSelection?>(
            get: {
                self.tabSelection
            },
            set: {
                self.tabSelection = $0 ?? .subscriptions
            }
        )
    }
}
