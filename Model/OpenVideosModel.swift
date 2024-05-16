#if canImport(AppKit)
    import AppKit
#endif
import Foundation
import Logging
#if canImport(UIKit)
    import UIKit
#endif
import SwiftUI

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

    static let shared = Self()
    var player: PlayerModel! = .shared
    var logger = Logger(label: "stream.yattee.open-videos")

    func open(_ url: URL) {
        if url.startAccessingSecurityScopedResource() {
            let video = Video.local(url)

            player.play([video], shuffling: false)
        }
    }

    var urlsFromClipboard: [URL] {
        #if os(iOS)
            if let pasteboard = UIPasteboard.general.urls {
                return pasteboard
            }
        #elseif os(macOS)
            if let pasteboard = NSPasteboard.general.string(forType: .string) {
                return urlsFrom(pasteboard)
            }
        #endif

        return []
    }

    func openURLsFromClipboard(removeQueueItems: Bool = false, playbackMode: Self.PlaybackMode = .playNow) {
        if urlsFromClipboard.isEmpty {
            NavigationModel.shared.alert = Alert(title: Text("Could not find any links to open in your clipboard".localized()))
            if NavigationModel.shared.presentingOpenVideos {
                NavigationModel.shared.presentingAlertInOpenVideos = true
            } else {
                NavigationModel.shared.presentingAlert = true
            }
        } else {
            openURLs(urlsFromClipboard, removeQueueItems: removeQueueItems, playbackMode: playbackMode)
        }
    }

    func openURLs(_ urls: [URL], removeQueueItems: Bool = false, playbackMode: Self.PlaybackMode = .playNow) {
        guard !urls.isEmpty else {
            return
        }

        NavigationModel.shared.presentingOpenVideos = false

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

        NavigationModel.shared.presentingChannelSheet = false

        if playbackMode == .playNow || playbackMode == .shuffleAll {
            #if os(iOS)
                if player.presentingPlayer {
                    player.advanceToNextItem()
                } else {
                    player.onPresentPlayer.append { [weak player] in player?.advanceToNextItem() }
                }
            #else
                player.advanceToNextItem()
            #endif
            player.show()
        }
    }

    func enqueue(_ urls: [URL], prepending: Bool = false) {
        var videos = urls.compactMap { url in
            var video: Video!
            if canOpenVideosByID {
                let parser = URLParser(url: url)

                if parser.destination == .video, let id = parser.videoID {
                    video = Video(app: .local, videoID: id)
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
        for video in videos {
            player.enqueueVideo(video, play: false, prepending: prepending, loadDetails: false)
        }
    }

    func urlsFrom(_ string: String) -> [URL] {
        string.split(whereSeparator: \.isNewline).compactMap { URL(string: String($0)) }
    }

    var canOpenVideosByID: Bool {
        guard let app = AccountsModel.shared.current?.app else { return false }
        return !AccountsModel.shared.isEmpty && app.supportsOpeningVideosByID
    }
}
