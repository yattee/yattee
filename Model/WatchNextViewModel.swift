import Combine
import Defaults
import Foundation
import SwiftUI

final class WatchNextViewModel: ObservableObject {
    enum Page: String, CaseIterable {
        case queue
        case related
        case history

        var title: String {
            rawValue.capitalized.localized()
        }

        var systemImageName: String {
            switch self {
            case .queue:
                return "list.and.film"
            case .related:
                return "rectangle.stack.fill"
            case .history:
                return "clock"
            }
        }
    }

    enum PresentationReason {
        case userInteracted
        case finishedWatching
        case closed
    }

    static let animation = Animation.easeIn(duration: 0.25)
    static let shared = WatchNextViewModel()

    @Published var item: PlayerQueueItem?
    @Published private(set) var isPresenting = false
    @Published var reason: PresentationReason?
    @Published var page = Page.queue

    @Published var countdown = 0.0
    var countdownTimer: Timer?

    var player = PlayerModel.shared

    var autoplayTimer: Timer?

    var isAutoplaying: Bool {
        reason == .finishedWatching
    }

    var isHideable: Bool {
        reason == .userInteracted
    }

    var isRestartable: Bool {
        player.currentItem != nil && reason != .userInteracted
    }

    var canAutoplay: Bool {
        switch player.playbackMode {
        case .shuffle:
            return !player.queue.isEmpty
        default:
            return nextFromTheQueue != nil
        }
    }

    func userInteractedOpen(_ item: PlayerQueueItem?) {
        self.item = item
        open(reason: .userInteracted)
    }

    func finishedWatching(_ item: PlayerQueueItem?, timer: Timer? = nil) {
        if canAutoplay {
            countdown = TimeInterval(Defaults[.openWatchNextOnFinishedWatchingDelay]) ?? 5.0
            resetCountdownTimer()
            autoplayTimer?.invalidate()
            autoplayTimer = timer
        } else {
            timer?.invalidate()
        }
        self.item = item
        open(reason: .finishedWatching)
    }

    func resetCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            guard self.countdown > 0 else {
                timer.invalidate()
                return
            }
            self.countdown = max(0, self.countdown - 1)
        }
    }

    func closed(_ item: PlayerQueueItem) {
        self.item = item
        open(reason: .closed)
    }

    func keepFromAutoplaying() {
        userInteractedOpen(item)
        cancelAutoplay()
    }

    func cancelAutoplay() {
        autoplayTimer?.invalidate()
        countdownTimer?.invalidate()
    }

    func restart() {
        cancelAutoplay()

        guard player.currentItem != nil else { return }

        if reason == .closed {
            hide()
            return
        }

        player.backend.seek(to: .zero, seekType: .loopRestart) { _ in
            self.hide()
            self.player.play()
        }
    }

    private func open(reason: PresentationReason) {
        self.reason = reason
        setPageAfterOpening()

        guard !isPresenting else { return }
        withAnimation(Self.animation) {
            isPresenting = true
        }
    }

    private func setPageAfterOpening() {
        let firstAvailable = Page.allCases.first { isAvailable($0) } ?? .history

        switch reason {
        case .finishedWatching:
            page = player.playbackMode == .related ? .queue : firstAvailable
        case .closed:
            page = player.playbackMode == .related ? .queue : firstAvailable
        default:
            page = firstAvailable
        }
    }

    func close() {
        let close = {
            self.player.closeCurrentItem()
            self.player.hide()
            Delay.by(0.5) {
                self.isPresenting = false
            }
        }
        if reason == .closed {
            close()
            return
        }
        if canAutoplay {
            cancelAutoplay()
            hide()
        } else {
            close()
        }
    }

    func hide() {
        guard isPresenting else { return }
        withAnimation(Self.animation) {
            isPresenting = false
        }
    }

    func resetItem() {
        item = nil
    }

    func isAvailable(_ page: Page) -> Bool {
        switch page {
        case .queue:
            return !player.queue.isEmpty
        case .related:
            guard let video = item?.video else { return false }
            return !video.related.isEmpty
        case .history:
            return true
        }
    }

    var nextFromTheQueue: PlayerQueueItem? {
        if player.playbackMode == .related {
            return player.autoplayItem
        } else if player.playbackMode == .queue {
            return player.queue.first
        }

        return nil
    }
}
