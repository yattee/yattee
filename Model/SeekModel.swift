import AVFoundation
import Foundation
import SwiftUI

final class SeekModel: ObservableObject {
    static let shared = SeekModel()

    @Published var currentTime = CMTime.zero
    @Published var duration = CMTime.zero

    @Published var lastSeekTime: CMTime? { didSet { onSeek() } }
    @Published var lastSeekType: SeekType?
    @Published var restoreSeekTime: CMTime?

    @Published var gestureSeek: Double?
    @Published var gestureStart: Double?

    @Published var presentingOSD = false

    var player: PlayerModel! { .shared }

    var dismissTimer: Timer?

    var isSeeking: Bool {
        gestureSeek != nil
    }

    var progress: Double {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return 0 }

        if isSeeking {
            return gestureSeekDestinationTime / seconds
        }

        guard let seekTime = lastSeekTime else {
            return currentTime.seconds / seconds
        }

        return seekTime.seconds / seconds
    }

    var lastSeekPlaybackTime: String {
        guard let time = lastSeekTime else { return 0.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? PlayerTimeModel.timePlaceholder }
        return time.seconds.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? PlayerTimeModel.timePlaceholder
    }

    var restoreSeekPlaybackTime: String {
        guard let time = restoreSeekTime else { return PlayerTimeModel.timePlaceholder }
        return time.seconds.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? PlayerTimeModel.timePlaceholder
    }

    var gestureSeekDestinationTime: Double {
        guard let gestureSeek, let gestureStart else { return -1 }
        return min(duration.seconds, max(0, gestureStart + gestureSeek))
    }

    var gestureSeekDestinationPlaybackTime: String {
        guard gestureSeek != 0 else { return PlayerTimeModel.timePlaceholder }
        return gestureSeekDestinationTime.formattedAsPlaybackTime(allowZero: true, forceHours: forceHours) ?? PlayerTimeModel.timePlaceholder
    }

    var durationPlaybackTime: String {
        if player?.currentItem.isNil ?? true {
            return PlayerTimeModel.timePlaceholder
        }

        return duration.seconds.formattedAsPlaybackTime() ?? PlayerTimeModel.timePlaceholder
    }

    func showOSD() {
        guard !presentingOSD else { return }

        presentingOSD = true
    }

    func hideOSD() {
        guard presentingOSD else { return }

        presentingOSD = false
    }

    func hideOSDWithDelay() {
        dismissTimer?.invalidate()
        dismissTimer = Delay.by(3) { self.hideOSD() }
    }

    func updateCurrentTime(completionHandler: (() -> Void?)? = nil) {
        player.backend.getTimeUpdates()
        DispatchQueue.main.async {
            self.currentTime = self.player.backend.currentTime ?? .zero
            self.duration = self.player.backend.playerItemDuration ?? .zero
            completionHandler?()
        }
    }

    func onSeekGestureStart() {
        updateCurrentTime {
            self.gestureStart = self.currentTime.seconds
            self.dismissTimer?.invalidate()
            self.showOSD()
        }
    }

    func onSeekGestureEnd() {
        dismissTimer?.invalidate()
        dismissTimer = Delay.by(3) { self.hideOSD() }
        player.backend.seek(to: gestureSeekDestinationTime, seekType: .userInteracted)
    }

    func onSeek() {
        guard !lastSeekTime.isNil else { return }
        gestureSeek = nil
        gestureStart = nil
        showOSD()
        hideOSDWithDelay()
    }

    func registerSeek(at time: CMTime, type: SeekType, restore restoreTime: CMTime? = nil) {
        updateCurrentTime {
            withAnimation {
                self.lastSeekTime = time
                self.lastSeekType = type
                self.restoreSeekTime = restoreTime
            }
        }
    }

    func restoreTime() {
        guard let time = restoreSeekTime else { return }
        switch lastSeekType {
        case .segmentSkip:
            player.restoreLastSkippedSegment()
        default:
            player.backend.seek(to: time, seekType: .userInteracted)
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
        gestureSeek = nil
    }

    var forceHours: Bool {
        duration.seconds >= 60 * 60
    }
}
