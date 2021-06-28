import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    @Default(.tabSelection) var tabSelection

    let video: Video

    var body: some View {
        if tabSelection == .channel {
            closeChannelButton(from: video)
        } else {
            openChannelButton(from: video)
        }
    }

    func openChannelButton(from video: Video) -> some View {
        Button("\(video.author) Channel") {
            Defaults[.openChannel] = Channel.from(video: video)
            tabSelection = .channel
        }
    }

    func closeChannelButton(from video: Video) -> some View {
        Button("Close \(Channel.from(video: video).name) Channel") {
            Defaults.reset(.openChannel)
        }
    }
}
