import AVFoundation
import Foundation

final class MuxedStream: Stream {
    var muxedAsset: AVURLAsset

    init(muxedAsset: AVURLAsset, resolution: StreamResolution, type: StreamType, encoding: String) {
        self.muxedAsset = muxedAsset

        super.init(audioAsset: muxedAsset, videoAsset: muxedAsset, resolution: resolution, type: type, encoding: encoding)
    }
}
