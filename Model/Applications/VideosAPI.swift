import AVFoundation
import Foundation
import Siesta

protocol VideosAPI {
    var account: Account! { get }
    var signedIn: Bool { get }

    func channel(_ id: String) -> Resource
    func channelVideos(_ id: String) -> Resource
    func trending(country: Country, category: TrendingCategory?) -> Resource
    func search(_ query: SearchQuery, page: String?) -> Resource
    func searchSuggestions(query: String) -> Resource

    func video(_ id: Video.ID) -> Resource

    var subscriptions: Resource? { get }
    var feed: Resource? { get }
    var home: Resource? { get }
    var popular: Resource? { get }
    var playlists: Resource? { get }

    func subscribe(_ channelID: String, onCompletion: @escaping () -> Void)
    func unsubscribe(_ channelID: String, onCompletion: @escaping () -> Void)

    func playlist(_ id: String) -> Resource?
    func playlistVideo(_ playlistID: String, _ videoID: String) -> Resource?
    func playlistVideos(_ id: String) -> Resource?

    func addVideoToPlaylist(
        _ videoID: String,
        _ playlistID: String,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping () -> Void
    )

    func removeVideoFromPlaylist(
        _ index: String,
        _ playlistID: String,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping () -> Void
    )

    func playlistForm(
        _ name: String,
        _ visibility: String,
        playlist: Playlist?,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping (Playlist?) -> Void
    )

    func deletePlaylist(
        _ playlist: Playlist,
        onFailure: @escaping (RequestError) -> Void,
        onSuccess: @escaping () -> Void
    )

    func channelPlaylist(_ id: String) -> Resource?

    func loadDetails(_ item: PlayerQueueItem, completionHandler: @escaping (PlayerQueueItem) -> Void)
    func shareURL(_ item: ContentItem, frontendHost: String?, time: CMTime?) -> URL?

    func comments(_ id: Video.ID, page: String?) -> Resource?
}

extension VideosAPI {
    func loadDetails(_ item: PlayerQueueItem, completionHandler: @escaping (PlayerQueueItem) -> Void = { _ in }) {
        guard (item.video?.streams ?? []).isEmpty else {
            completionHandler(item)
            return
        }

        video(item.videoID).load().onSuccess { response in
            guard let video: Video = response.typedContent() else {
                return
            }

            var newItem = item
            newItem.video = video

            completionHandler(newItem)
        }
    }

    func shareURL(_ item: ContentItem, frontendHost: String? = nil, time: CMTime? = nil) -> URL? {
        guard let frontendHost = frontendHost ?? account?.instance?.frontendHost,
              var urlComponents = account?.instance?.urlComponents
        else {
            return nil
        }

        urlComponents.host = frontendHost

        var queryItems = [URLQueryItem]()

        switch item.contentType {
        case .video:
            urlComponents.path = "/watch"
            queryItems.append(.init(name: "v", value: item.video.videoID))
        case .channel:
            urlComponents.path = "/channel/\(item.channel.id)"
        case .playlist:
            urlComponents.path = "/playlist"
            queryItems.append(.init(name: "list", value: item.playlist.id))
        default:
            return nil
        }

        if !time.isNil, time!.seconds.isFinite {
            queryItems.append(.init(name: "t", value: "\(Int(time!.seconds))s"))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        return urlComponents.url
    }

    func extractChapters(from description: String) -> [Chapter] {
        guard let chaptersRegularExpression = try? NSRegularExpression(
            pattern: "(?<start>(?:[0-9]+:){1,}(?:[0-9]+))(?:\\s)+(?:- ?)?(?<title>.*)",
            options: .caseInsensitive
        ) else { return [] }

        let chapterLines = chaptersRegularExpression.matches(
            in: description,
            range: NSRange(description.startIndex..., in: description)
        )

        return chapterLines.compactMap { line in
            let titleRange = line.range(withName: "title")
            let startRange = line.range(withName: "start")

            guard let titleSubstringRange = Range(titleRange, in: description),
                  let startSubstringRange = Range(startRange, in: description),
                  let titleCapture = String(description[titleSubstringRange]),
                  let startCapture = String(description[startSubstringRange]) else { return nil }

            let startComponents = startCapture.components(separatedBy: ":")
            guard startComponents.count <= 3 else { return nil }

            var hours: Double?
            var minutes: Double?
            var seconds: Double?

            if startComponents.count == 3 {
                hours = Double(startComponents[0])
                minutes = Double(startComponents[1])
                seconds = Double(startComponents[2])
            } else if startComponents.count == 2 {
                minutes = Double(startComponents[0])
                seconds = Double(startComponents[1])
            }

            guard var startSeconds = seconds else { return nil }

            if let minutes = minutes {
                startSeconds += 60 * minutes
            }

            if let hours = hours {
                startSeconds += 60 * 60 * hours
            }

            return .init(title: titleCapture, start: startSeconds)
        }
    }
}
