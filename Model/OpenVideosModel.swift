import Foundation
import Logging

struct OpenVideosModel {
    enum PlaybackMode: String, CaseIterable {
        case playNow
        case shuffleAll
        case playNext
        case playLast

        var description: String {
            switch self {
            case .playNow:
                return "Play Now".localized()
            case .shuffleAll:
                return "Shuffle All".localized()
            case .playNext:
                return "Play Next".localized()
            case .playLast:
                return "Play Last".localized()
            }
        }

        var allowsRemovingQueueItems: Bool {
            self == .playNow || self == .shuffleAll
        }

        var allowedWhenQueueIsEmpty: Bool {
            self == .playNow || self == .shuffleAll
        }
    }

    static let shared = OpenVideosModel()
    var player: PlayerModel! = .shared
    var logger = Logger(label: "stream.yattee.open-videos")

    func open(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            let video = Video.local(url)

            player.play([video], shuffling: false)
        }
    }

    func openURLs(_ urls: [URL], removeQueueItems: Bool, playbackMode: OpenVideosModel.PlaybackMode) {
        logger.info("opening \(urls.count) urls")
        urls.forEach { logger.info("\($0.absoluteString)") }

        if removeQueueItems, playbackMode.allowsRemovingQueueItems {
            player.removeQueueItems()
            logger.info("removing queue items")
        }

        switch playbackMode {
        case .playNow:
            player.playbackMode = .queue
        case .shuffleAll:
            player.playbackMode = .shuffle
        case .playNext:
            player.playbackMode = .queue
        case .playLast:
            player.playbackMode = .queue
        }

        enqueue(
            urls,
            prepending: playbackMode == .playNow || playbackMode == .playNext
        )

        if playbackMode == .playNow || playbackMode == .shuffleAll {
            player.show()
            player.advanceToNextItem()
        }
    }

    func enqueue(_ urls: [URL], prepending: Bool = false) {
        var videos = urls.compactMap { url in
            var video: Video!
            if canOpenVideosByID {
                let parser = URLParser(url: url)

                if parser.destination == .video, let id = parser.videoID {
                    video = Video(videoID: id)
                    logger.info("identified remote video: \(id)")
                } else {
                    video = .local(url)
                    logger.info("identified local video: \(url.absoluteString)")
                }
            } else {
                video = .local(url)
                logger.info("identified local video: \(url.absoluteString)")
            }

            return video
        }

        if prepending {
            videos.reverse()
        }
        videos.forEach { video in
            player.enqueueVideo(video, play: false, prepending: prepending, loadDetails: false)
        }
    }

    var canOpenVideosByID: Bool {
        guard let app = player.accounts.current?.app else { return false }
        return !player.accounts.isEmpty && app.supportsOpeningVideosByID
    }
}
