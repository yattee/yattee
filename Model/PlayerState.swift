import AVFoundation
import Foundation
import Logging

final class PlayerState: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    var video: Video

    @Published private(set) var currentStream: Stream!
    @Published var streamToLoad: Stream!

    @Published var savedTime: CMTime?

    @Published var streamLoading = false

    @Published var player = AVPlayer()
    var composition = AVMutableComposition()

    var playerItem: AVPlayerItem {
        let playerItem = AVPlayerItem(asset: composition)

        playerItem.externalMetadata = [makeMetadataItem(.commonIdentifierTitle, value: video.title)]
        playerItem.preferredForwardBufferDuration = 10

        return playerItem
    }

    init(_ video: Video) {
        self.video = video
    }

    func cancelLoadingStream(_ stream: Stream) {
        guard streamToLoad == stream else {
            return
        }

        streamToLoad = nil
        streamLoading = false

        logger.info("cancel streamToLoad: \(streamToLoad?.description ?? "nil"), streamLoading \(streamLoading)")
    }

    func loadStream(_ stream: Stream?) {
        guard streamToLoad != stream else {
            return
        }

        streamToLoad?.cancelLoadingAssets()

        DispatchQueue.main.async {
            self.streamLoading = true
            self.streamToLoad = stream
        }
        logger.info("replace streamToLoad: \(streamToLoad?.description ?? "nil"), streamLoading \(streamLoading)")
    }

    func streamDidLoad(_ stream: Stream?) {
        logger.info("didload stream: \(stream!.description)")
        logger.info("before: toLoad: \(streamToLoad?.description ?? "nil"), current \(currentStream?.description ?? "nil"), loading \(streamLoading)")

        currentStream = stream
        streamLoading = streamToLoad != stream

        if streamToLoad == stream {
            streamToLoad = nil
        }

        logger.info("after: toLoad: \(streamToLoad?.description ?? "nil"), current \(currentStream?.description ?? "nil"), loading \(streamLoading)")
    }

    func loadStreamIntoPlayer(_ stream: Stream) {
        logger.warning("loading \(stream.description) to player")

        beforeLoadStreamIntoPlayer()

        player.replaceCurrentItem(with: playerItem)
        streamDidLoad(stream)

        afterLoadStreamIntoPlayer()
    }

    func beforeLoadStreamIntoPlayer() {
        let currentTime = player.currentTime()

        guard currentTime.seconds > 0 else {
            return
        }

        savedTime = currentTime
    }

    func afterLoadStreamIntoPlayer() {
        if let time = savedTime {
            player.seek(to: time)
        }

        player.play()
    }

    private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
        let item = AVMutableMetadataItem()

        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        item.extendedLanguageTag = "und"

        return item.copy() as! AVMetadataItem
    }
}
