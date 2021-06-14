import AVFoundation
import Foundation

// swiftlint:disable:next final_class
class Stream: Equatable {
    var audioAsset: AVURLAsset
    var videoAsset: AVURLAsset

    var resolution: StreamResolution
    var type: StreamType

    var encoding: String

    init(audioAsset: AVURLAsset, videoAsset: AVURLAsset, resolution: StreamResolution, type: StreamType, encoding: String) {
        self.audioAsset = audioAsset
        self.videoAsset = videoAsset
        self.resolution = resolution
        self.type = type
        self.encoding = encoding
    }

    var description: String {
        "\(resolution.height)p"
    }

    static func == (lhs: Stream, rhs: Stream) -> Bool {
        lhs.resolution == rhs.resolution && lhs.type == rhs.type
    }
}
