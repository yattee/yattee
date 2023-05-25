import Defaults
import Foundation
import SwiftUI

struct WatchView: View {
    var watch: Watch?
    var videoID: Video.ID
    var duration: Double

    @Default(.watchedVideoBadgeColor) private var watchedVideoBadgeColor
    @Default(.showToggleWatchedStatusButton) private var showToggleWatchedStatusButton

    var backgroundContext = PersistenceController.shared.container.newBackgroundContext()

    var body: some View {
        if showToggleWatchedStatusButton {
            #if os(tvOS)
                if finished {
                    image
                }
            #else
                Button(action: toggleWatch) {
                    image
                }
                .opacity(finished ? 1 : 0.4)
                .buttonStyle(.plain)
            #endif
        } else {
            if finished {
                image
            }
        }
    }

    var image: some View {
        Image(systemName: imageSystemName)
            .foregroundColor(Color(
                watchedVideoBadgeColor == .colorSchemeBased ? "WatchProgressBarColor" :
                    watchedVideoBadgeColor == .red ? "AppRedColor" : "AppBlueColor"
            ))
            .background(backgroundColor)
            .clipShape(Circle())
            .imageScale(.large)
    }

    func toggleWatch() {
        if finished, let watch {
            PlayerModel.shared.removeWatch(watch)
        } else {
            if let account = AccountsModel.shared.current {
                Watch.markAsWatched(videoID: watch?.videoID ?? videoID, account: account, duration: watch?.videoDuration ?? duration, context: backgroundContext)
            }
        }

        FeedModel.shared.calculateUnwatchedFeed()
        WatchModel.shared.watchesChanged()
    }

    var imageSystemName: String {
        finished ? "checkmark.circle.fill" : "circle"
    }

    var backgroundColor: Color {
        finished ? .white : .clear
    }

    var finished: Bool {
        guard let watch else { return false }
        return watch.finished
    }
}

struct WatchView_Previews: PreviewProvider {
    static var previews: some View {
        WatchView(videoID: "abc", duration: 10)
    }
}
