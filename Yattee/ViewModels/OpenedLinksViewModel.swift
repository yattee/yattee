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
        var seen = Set<String>()
        let unique = urls.filter { seen.insert($0.absoluteString).inserted }
        links = unique.enumerated().map { OpenedLink(id: $0.offset, url: $0.element) }
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

    var isLoading: Bool {
        links.contains { link in
            if case .loading = link.state { return true }
            return false
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

        case .playlist(.remote(let playlistID, let instance, _, _)):
            guard let instance = instance
                    ?? playlistID.source.flatMap({ appEnvironment.instancesManager.playlistInstance(for: $0) }) else {
                return .unresolved(destination, message: String(localized: "openLink.noInstance"))
            }
            do {
                let playlist = try await appEnvironment.contentService.playlist(id: playlistID.playlistID, instance: instance)
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
