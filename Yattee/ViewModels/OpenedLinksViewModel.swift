//
//  OpenedLinksViewModel.swift
//  Yattee
//
//  Resolves several opened links into videos, playlists and channels for
//  the Opened Links page.
//

import Foundation

/// One link on the Opened Links page, in the order it was entered.
struct OpenedLink: Identifiable {
    enum State {
        case loading
        case video(Video)
        case playlist(Playlist, destination: NavigationDestination)
        case channel(Channel, destination: NavigationDestination)
        /// A screen the link opens whose details couldn't be loaded here
        /// (the screen itself shows why).
        case unresolved(NavigationDestination, message: String)
        case failed(String)
    }

    let id: Int
    let url: URL
    var state: State = .loading
}

@Observable
@MainActor
final class OpenedLinksViewModel {
    private(set) var links: [OpenedLink]
    private var hasStarted = false

    /// Links resolved at once - extraction on Yattee Server is slow, but
    /// one link at a time would make long lists crawl.
    private static let maxConcurrentResolutions = 4

    init(urls: [URL]) {
        // A watch link inside a playlist (`watch?v=X&list=Y`) shows both the
        // video and the playlist
        let router = URLRouter()
        let expanded = urls.flatMap { url -> [URL] in
            guard let listID = router.youTubePlaylistContext(url),
                  let playlistURL = Self.youTubePlaylistURL(listID) else { return [url] }
            return [url, playlistURL]
        }
        var seen = Set<String>()
        let unique = expanded.filter { seen.insert($0.absoluteString).inserted }
        links = unique.enumerated().map { OpenedLink(id: $0.offset, url: $0.element) }
    }

    private static func youTubePlaylistURL(_ listID: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/playlist")
        components?.queryItems = [URLQueryItem(name: "list", value: listID)]
        return components?.url
    }

    /// Resolved videos, in link order.
    var videos: [Video] {
        links.compactMap { link in
            if case .video(let video) = link.state { return video }
            return nil
        }
    }

    /// Links of the videos in `videos`, for re-resolving their streams.
    var videoLinks: [URL] {
        links.compactMap { link in
            if case .video = link.state { return link.url }
            return nil
        }
    }

    /// Starts resolving once. Owned by the model rather than the view's
    /// `.task`, which is cancelled when a result's screen is pushed and would
    /// fail the links still loading.
    func start(appEnvironment: AppEnvironment) {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await load(appEnvironment: appEnvironment) }
    }

    private func load(appEnvironment: AppEnvironment) async {

        let links = self.links
        await withTaskGroup(of: (Int, OpenedLink.State).self) { group in
            var next = 0
            func enqueueNext() {
                guard next < links.count else { return }
                let link = links[next]
                next += 1
                group.addTask { @MainActor in
                    (link.id, await Self.resolve(link.url, appEnvironment: appEnvironment))
                }
            }

            for _ in 0..<Self.maxConcurrentResolutions { enqueueNext() }

            for await (id, state) in group {
                if let index = self.links.firstIndex(where: { $0.id == id }) {
                    self.links[index].state = state
                }
                enqueueNext()
            }
        }
    }

    private static func resolve(_ url: URL, appEnvironment: AppEnvironment) async -> OpenedLink.State {
        let destination: NavigationDestination
        do {
            destination = try await LinkVideoResolver(appEnvironment: appEnvironment).resolveDestination(url)
        } catch {
            return .failed(error.localizedDescription)
        }

        switch destination {
        case .video(.loaded(let video), _):
            return .video(video)

        case .playlist(let source):
            do {
                let playlist = try await LinkVideoResolver(appEnvironment: appEnvironment).playlist(for: source)
                return .playlist(playlist, destination: destination)
            } catch {
                return .unresolved(destination, message: error.localizedDescription)
            }

        case .channel(let channelID, let source):
            guard let instance = appEnvironment.instancesManager.instance(for: source) else {
                return .unresolved(destination, message: String(localized: "openLink.noInstance"))
            }
            do {
                let channel = try await appEnvironment.contentService.channel(id: channelID, instance: instance)
                return .channel(channel, destination: destination)
            } catch {
                return .unresolved(destination, message: error.localizedDescription)
            }

        default:
            return .unresolved(destination, message: url.absoluteString)
        }
    }
}
