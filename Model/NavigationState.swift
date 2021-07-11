import Foundation
import SwiftUI

final class NavigationState: ObservableObject {
    @Published var tabSelection: TabSelection = .subscriptions

    @Published var showingChannel = false
    @Published var channel: Channel?

    @Published var showingVideoDetails = false
    @Published var video: Video?

    func openChannel(_ channel: Channel) {
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
