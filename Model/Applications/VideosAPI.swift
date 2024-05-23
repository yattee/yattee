import AVFoundation
import Foundation
import Siesta

protocol VideosAPI {
    var account: Account! { get }
    var signedIn: Bool { get }

    static func withAnonymousAccountForInstanceURL(_ url: URL) -> Self

    func channel(_ id: String, contentType: Channel.ContentType, data: String?, page: String?) -> Resource
    func channelByName(_ name: String) -> Resource?
    func channelByUsername(_ username: String) -> Resource?
    func channelVideos(_ id: String) -> Resource
    func trending(country: Country, category: TrendingCategory?) -> Resource
    func search(_ query: SearchQuery, page: String?) -> Resource
    func searchSuggestions(query: String) -> Resource

    func video(_ id: Video.ID) -> Resource

    func feed(_ page: Int?) -> Resource?
    var subscriptions: Resource? { get }
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

    func loadDetails(
        _ item: PlayerQueueItem,
        failureHandler: ((RequestError) -> Void)?,
        completionHandler: @escaping (PlayerQueueItem) -> Void
    )
    func shareURL(_ item: ContentItem, frontendURLString: String?, time: CMTime?) -> URL?

    func comments(_ id: Video.ID, page: String?) -> Resource?
}

extension VideosAPI {
    func channel(_ id: String, contentType: Channel.ContentType, data: String? = nil, page: String? = nil) -> Resource {
        channel(id, contentType: contentType, data: data, page: page)
    }

    func loadDetails(
        _ item: PlayerQueueItem,
        failureHandler: ((RequestError) -> Void)? = nil,
        completionHandler: @escaping (PlayerQueueItem) -> Void = { _ in }
    ) {
        guard (item.video?.streams ?? []).isEmpty else {
            completionHandler(item)
            return
        }

        if let video = item.video, video.isLocal {
            completionHandler(item)
            return
        }

        video(item.videoID).load()
            .onSuccess { response in
                guard let video: Video = response.typedContent() else {
                    return
                }

                VideosCacheModel.shared.storeVideo(video)

                var newItem = item
                newItem.id = UUID()
                newItem.video = video

                completionHandler(newItem)
            }
            .onFailure { failureHandler?($0) }
    }

    func shareURL(_ item: ContentItem, frontendURLString: String? = nil, time: CMTime? = nil) -> URL? {
        var urlComponents: URLComponents?
        if let frontendURLString,
           let frontendURL = URL(string: frontendURLString)
        {
            urlComponents = URLComponents(url: frontendURL, resolvingAgainstBaseURL: false)
        } else if let instanceComponents = account?.instance?.urlComponents {
            urlComponents = instanceComponents
        }

        guard var urlComponents else {
            return nil
        }

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
        /*
         The following chapter patterns are covered:

         1) "start - end - title" / "start - end: Title" / "start - end title"
         2) "start - title" / "start: title" / "start title" / "[start] - title" / "[start]: title" / "[start] title"
         3) "index. title - start" / "index. title start"
         4) "title: (start)"
         5) "(start) title"

         These represent:

         -  "start" and "end" are timestamps, defining the start and end of the individual chapter
         -  "title" is the name of the chapter
         -  "index" is the chapter's position in a list

         The order of these patterns is important as it determines the priority. The patterns listed first have a higher priority.
         In the case of multiple matches, the pattern with the highest priority will be chosen - lower number means higher priority.
         */
        let patterns = [
            "(?<=\\n|^)\\s*(?:►\\s*)?\\[?(?<start>(?:[0-9]+:){1,2}[0-9]+)\\]?(?:\\s*-\\s*)?(?<end>(?:[0-9]+:){1,2}[0-9]+)?(?:\\s*-\\s*|\\s*[:]\\s*)?(?<title>.*)(?=\\n|$)",
            "(?<=\\n|^)\\s*(?:►\\s*)?\\[?(?<start>(?:[0-9]+:){1,2}[0-9]+)\\]?\\s*[-:]?\\s*(?<title>.+)(?=\\n|$)",
            "(?<=\\n|^)(?<index>[0-9]+\\.\\s)(?<title>.+?)(?:\\s*-\\s*)?(?<start>(?:[0-9]+:){1,2}[0-9]+)(?=\\n|$)",
            "(?<=\\n|^)(?<title>.+?):\\s*\\((?<start>(?:[0-9]+:){1,2}[0-9]+)\\)(?=\\n|$)",
            "(?<=^|\\n)\\((?<start>(?:[0-9]+:){1,2}[0-9]+)\\)\\s*(?<title>.+?)(?=\\n|$)"
        ]

        let extractChaptersGroup = DispatchGroup()
        var capturedChapters: [Int: [Chapter]] = [:]
        let lock = NSLock()

        for (index, pattern) in patterns.enumerated() {
            extractChaptersGroup.enter()
            DispatchQueue.global().async {
                if let chaptersRegularExpression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let chapterLines = chaptersRegularExpression.matches(in: description, range: NSRange(description.startIndex..., in: description))
                    let extractedChapters = chapterLines.compactMap { line -> Chapter? in
                        let titleRange = line.range(withName: "title")
                        let startRange = line.range(withName: "start")

                        guard let titleSubstringRange = Range(titleRange, in: description),
                              let startSubstringRange = Range(startRange, in: description)
                        else {
                            return nil
                        }

                        let titleCapture = String(description[titleSubstringRange]).trimmingCharacters(in: .whitespaces)
                        let startCapture = String(description[startSubstringRange])
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

                        startSeconds += (minutes ?? 0) * 60
                        startSeconds += (hours ?? 0) * 60 * 60

                        return Chapter(title: titleCapture, start: startSeconds)
                    }

                    if !extractedChapters.isEmpty {
                        lock.lock()
                        capturedChapters[index] = extractedChapters
                        lock.unlock()
                    }
                }
                extractChaptersGroup.leave()
            }
        }

        extractChaptersGroup.wait()

        // Now we sort the keys of the capturedChapters dictionary.
        // These keys correspond to the priority of each pattern.
        let sortedKeys = Array(capturedChapters.keys).sorted(by: <)

        // Return first non-empty result in the order of patterns
        for key in sortedKeys {
            if let chapters = capturedChapters[key], !chapters.isEmpty {
                return chapters
            }
        }
        return []
    }
}
