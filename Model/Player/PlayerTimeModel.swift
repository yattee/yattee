import CoreMedia
import Foundation

final class PlayerTimeModel: ObservableObject {
    static let timePlaceholder = "--:--"

    @Published var currentTime = CMTime.zero
    @Published var duration = CMTime.zero

    var player: PlayerModel?

    var currentPlaybackTime: String {
        if player?.currentItem.isNil ?? true || duration.seconds.isZero {
            return Self.timePlaceholder
        }

        return currentTime.seconds.formattedAsPlaybackTime(allowZero: true) ?? Self.timePlaceholder
    }

    var durationPlaybackTime: String {
        if player?.currentItem.isNil ?? true {
            return Self.timePlaceholder
        }

        return duration.seconds.formattedAsPlaybackTime() ?? Self.timePlaceholder
    }

    var withoutSegmentsPlaybackTime: String {
        guard let withoutSegmentsDuration = player?.playerItemDurationWithoutSponsorSegments?.seconds else {
            return Self.timePlaceholder
        }

        return withoutSegmentsDuration.formattedAsPlaybackTime() ?? Self.timePlaceholder
    }

    var durationAndWithoutSegmentsPlaybackTime: String {
        var durationAndWithoutSegmentsPlaybackTime = "\(durationPlaybackTime)"

        if withoutSegmentsPlaybackTime != durationPlaybackTime {
            durationAndWithoutSegmentsPlaybackTime += " (\(withoutSegmentsPlaybackTime))"
        }

        return durationAndWithoutSegmentsPlaybackTime
    }

    func reset() {
        currentTime = .zero
        duration = .zero
    }
}
