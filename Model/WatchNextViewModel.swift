import Foundation
import SwiftUI

final class WatchNextViewModel: ObservableObject {
    static let animation = Animation.easeIn(duration: 0.25)
    static let shared = WatchNextViewModel()

    @Published var item: PlayerQueueItem?
    @Published var presentingOutro = true
    @Published var isAutoplaying = true
    var timer: Timer?

    func prepareForEmptyPlayerPlaceholder(_ item: PlayerQueueItem? = nil) {
        self.item = item
    }

    func prepareForNextItem(_ item: PlayerQueueItem? = nil, timer: Timer? = nil) {
        self.item = item
        self.timer?.invalidate()
        self.timer = timer
        isAutoplaying = true
        withAnimation(Self.animation) {
            presentingOutro = true
        }
    }

    func cancelAutoplay() {
        timer?.invalidate()
        isAutoplaying = false
    }

    func open() {
        withAnimation(Self.animation) {
            presentingOutro = true
        }
    }

    func close() {
        withAnimation(Self.animation) {
            presentingOutro = false
        }
    }

    func resetItem() {
        item = nil
    }
}
