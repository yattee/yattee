import Foundation

class AppState: ObservableObject {
    @Published var showingChannel = false
    @Published var channelID: String = ""
    @Published var channel: String = ""

    func openChannel(from video: Video) {
        channel = video.author
        channelID = video.channelID
        showingChannel = true
    }

    func closeChannel() {
        showingChannel = false
        channel = ""
        channelID = ""
    }
}
