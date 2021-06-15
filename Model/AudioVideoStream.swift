import AVFoundation
import Foundation

final class AudioVideoStream: Stream {
    var avAsset: AVURLAsset

    init(avAsset: AVURLAsset, resolution: StreamResolution, type: StreamType, encoding: String) {
        self.avAsset = avAsset

        super.init(audioAsset: avAsset, videoAsset: avAsset, resolution: resolution, type: type, encoding: encoding)
    }
}
