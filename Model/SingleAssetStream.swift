import AVFoundation
import Foundation

final class SingleAssetStream: Stream {
    var avAsset: AVURLAsset

    init(instance: Instance? = nil, avAsset: AVURLAsset, resolution: Resolution, kind: Kind, encoding: String = "", videoFormat: String? = nil) {
        self.avAsset = avAsset

        super.init(instance: instance, audioAsset: avAsset, videoAsset: avAsset, resolution: resolution, kind: kind, encoding: encoding, videoFormat: videoFormat)
    }
}
