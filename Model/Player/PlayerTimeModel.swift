import CoreMedia
import Foundation
import SwiftUI

final class PlayerTimeModel: ObservableObject {
    static let shared = PlayerTimeModel()
    static let timePlaceholder = "--:--"

    @Published var currentTime = CMTime.zero
    @Published var duration = CMTime.zero

    var player: PlayerModel { .shared }

    var forceHours: Bool {
        duration.seconds >= 60 * 60
    }

    var currentPlaybackTime: String {
        if player.currentItem.isNil || duration.seconds.isZero {
            return Self.timePlaceholder
        }

        return currentTime.seconds.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? Self.timePlaceholder
    }

    var durationPlaybackTime: String {
        if player.currentItem.isNil {
            return Self.timePlaceholder
        }

        return duration.seconds.formattedAsPlaybackTime() ?? Self.timePlaceholder
    }

    var withoutSegmentsPlaybackTime: String {
        guard let withoutSegmentsDuration = player.playerItemDurationWithoutSponsorSegments?.seconds else { return Self.timePlaceholder }
        return withoutSegmentsDuration.formattedAsPlaybackTime(forceHours: forceHours) ?? Self.timePlaceholder
    }
}
