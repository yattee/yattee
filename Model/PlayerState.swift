import AVFoundation
import Foundation
import Logging

final class PlayerState: ObservableObject {
    let logger = Logger(label: "net.arekf.Pearvidious.ps")

    @Published private(set) var currentStream: Stream!
    @Published var streamToLoad: Stream!

    @Published var seekTo: CMTime?

    @Published var streamLoading = false

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

        streamLoading = true
        streamToLoad = stream

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
}
