import CoreMedia
import Foundation
import SwiftUI

final class PlayerTimeModel: ObservableObject {
    enum SeekType: Equatable {
        case segmentSkip(String)
        case segmentRestore
        case userInteracted
        case loopRestart
        case backendSync

        var presentable: Bool {
            self != .backendSync
        }
    }

    static let timePlaceholder = "--:--"

    @Published var currentTime = CMTime.zero
    @Published var duration = CMTime.zero

    @Published var lastSeekTime: CMTime?
    @Published var lastSeekType: SeekType?
    @Published var restoreSeekTime: CMTime?

    @Published var gestureSeek = 0.0
    @Published var gestureStart = 0.0

    @Published var seekOSDDismissed = true

    var player: PlayerModel!

    var forceHours: Bool {
        duration.seconds >= 60 * 60
    }

    var currentPlaybackTime: String {
        if player?.currentItem.isNil ?? true || duration.seconds.isZero {
            return Self.timePlaceholder
        }

        return currentTime.seconds.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? Self.timePlaceholder
    }

    var durationPlaybackTime: String {
        if player?.currentItem.isNil ?? true {
            return Self.timePlaceholder
        }

        return duration.seconds.formattedAsPlaybackTime() ?? Self.timePlaceholder
    }

    var withoutSegmentsPlaybackTime: String {
        guard let withoutSegmentsDuration = player?.playerItemDurationWithoutSponsorSegments?.seconds else { return Self.timePlaceholder }
        return withoutSegmentsDuration.formattedAsPlaybackTime(forceHours: forceHours) ?? Self.timePlaceholder
    }

    var lastSeekPlaybackTime: String {
        guard let time = lastSeekTime else { return 0.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? Self.timePlaceholder }
        return time.seconds.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? Self.timePlaceholder
    }

    var restoreSeekPlaybackTime: String {
        guard let time = restoreSeekTime else { return Self.timePlaceholder }
        return time.seconds.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? Self.timePlaceholder
    }

    var gestureSeekDestinationTime: Double {
        min(duration.seconds, max(0, gestureStart + gestureSeek))
    }

    var gestureSeekDestinationPlaybackTime: String {
        guard gestureSeek != 0 else { return Self.timePlaceholder }
        return gestureSeekDestinationTime.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? Self.timePlaceholder
    }

    func onSeekGestureStart(completionHandler: (() -> Void)? = nil) {
        player.backend.getTimeUpdates()
        player.backend.updateControls {
            self.gestureStart = self.currentTime.seconds
            completionHandler?()
        }
    }

    func onSeekGestureEnd() {
        player.backend.updateControls()
        player.backend.seek(to: gestureSeekDestinationTime, seekType: .userInteracted)
    }

    func registerSeek(at time: CMTime, type: SeekType, restore restoreTime: CMTime? = nil) {
        DispatchQueue.main.async { [weak self] in
            withAnimation {
                self?.lastSeekTime = time
                self?.lastSeekType = type
                self?.restoreSeekTime = restoreTime
            }
        }
    }

    func restoreTime() {
        guard let time = restoreSeekTime else { return }
        switch lastSeekType {
        case .segmentSkip:
            player.restoreLastSkippedSegment()
        default:
            player?.backend.seek(to: time, seekType: .userInteracted)
        }
    }

    func resetSeek() {
        withAnimation {
            lastSeekTime = nil
            lastSeekType = nil
        }
    }

    func reset() {
        currentTime = .zero
        duration = .zero
        resetSeek()
        gestureSeek = 0
    }
}
