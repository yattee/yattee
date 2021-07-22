import AVFoundation
import Foundation

final class SingleAssetStream: Stream {
    var avAsset: AVURLAsset

    init(avAsset: AVURLAsset, resolution: Resolution, kind: Kind, encoding: String) {
        self.avAsset = avAsset

        super.init(audioAsset: avAsset, videoAsset: avAsset, resolution: resolution, kind: kind, encoding: encoding)
    }
}
