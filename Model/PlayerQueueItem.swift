import AVFoundation
import Foundation

struct PlayerQueueItem: Hashable, Identifiable {
    var id = UUID()
    var video: Video

    init(_ video: Video) {
        self.video = video
    }

    var playerItems = [AVPlayerItem]()
    var compositions = [Stream: AVMutableComposition]()
}
