//
//  LinkActionPerformer.swift
//  Yattee
//
//  Runs URL scheme actions (`LinkAction`) and reports what happened, so the
//  same code serves plain links now and x-callback-url callers later.
//

import Foundation

@MainActor
struct LinkActionPerformer {
    let appEnvironment: AppEnvironment

    func perform(_ action: LinkAction) async -> LinkActionResult {
        LoggingService.shared.info("Link action: \(action)", category: .general)
        let result: LinkActionResult
        switch action {
        case .play(let url, let startTime):
            result = await play(url, startTime: startTime)
        case .playNext(let url):
            result = await queue(url, next: true)
        case .addToQueue(let url):
            result = await queue(url, next: false)
        case .download(let url):
            result = await download(url)
        case .bookmark(let url):
            result = await bookmark(url)
        case .subscribe(let url):
            result = await setSubscribed(true, channelURL: url)
        case .unsubscribe(let url):
            result = await setSubscribed(false, channelURL: url)
        case .player(let command):
            result = await perform(command)
        }
        report(result)
        return result
    }

    // MARK: - Video Actions

    private func play(_ url: URL, startTime: TimeInterval?) async -> LinkActionResult {
        let resolved: Video
        switch await resolve(url) {
        case .success(let video): resolved = video.0
        case .failure(let failure): return failure.result
        }
        appEnvironment.playerService.openVideo(resolved, startTime: startTime, forceStartTime: startTime != nil)
        return .success(values(for: resolved))
    }

    private func queue(_ url: URL, next: Bool) async -> LinkActionResult {
        let queueManager = appEnvironment.queueManager
        guard queueManager.isQueueEnabled else {
            return .failure(code: "queueDisabled", message: String(localized: "linkAction.error.queueDisabled", defaultValue: "The queue is turned off in Settings."))
        }
        let video: Video
        switch await resolve(url) {
        case .success(let resolved): video = resolved.0
        case .failure(let failure): return failure.result
        }
        let confirmed = await confirm(
            title: next
                ? String(localized: "linkAction.confirm.playNext.title", defaultValue: "Play Next?")
                : String(localized: "linkAction.confirm.queue.title", defaultValue: "Add to Queue?"),
            subject: video.title,
            detail: video.author.name,
            confirmTitle: next
                ? String(localized: "linkAction.confirm.playNext.button", defaultValue: "Play Next")
                : String(localized: "linkAction.confirm.queue.button", defaultValue: "Add to Queue"),
            systemImage: next ? "text.line.first.and.arrowtriangle.forward" : "text.append"
        )
        guard confirmed else { return .cancelled }

        if next {
            queueManager.playNext(video, queueSource: .manual)
        } else {
            queueManager.addToQueue(video, queueSource: .manual)
        }
        appEnvironment.toastManager.showSuccess(
            next
                ? String(localized: "linkAction.done.playNext", defaultValue: "Playing next")
                : String(localized: "linkAction.done.queue", defaultValue: "Added to queue"),
            subtitle: video.title
        )
        return .success(values(for: video))
    }

    private func download(_ url: URL) async -> LinkActionResult {
        #if os(tvOS)
        return .failure(code: "unsupported", message: String(localized: "linkAction.error.downloadUnsupported", defaultValue: "Downloads aren't available on this device."))
        #else
        let video: Video, streams: [Stream], captions: [Caption], storyboards: [Storyboard]
        switch await resolve(url) {
        case .success(let resolved): (video, streams, captions, storyboards) = resolved
        case .failure(let failure): return failure.result
        }

        let downloadSettings = appEnvironment.downloadSettings
        // The quality picker is already a confirmation: nothing is saved until
        // the user picks
        guard downloadSettings.preferredDownloadQuality != .ask else {
            appEnvironment.navigationCoordinator.presenter.present(.downloadOptions(video, streams: streams, captions: captions))
            return .success(values(for: video).merging(["status": "picking"]) { $1 })
        }

        let confirmed = await confirm(
            title: String(localized: "linkAction.confirm.download.title", defaultValue: "Download Video?"),
            subject: video.title,
            detail: video.author.name,
            confirmTitle: String(localized: "linkAction.confirm.download.button", defaultValue: "Download"),
            systemImage: "arrow.down.circle"
        )
        guard confirmed else { return .cancelled }

        do {
            try await LinkVideoResolver(appEnvironment: appEnvironment).enqueueDownload(
                video: video,
                streams: streams,
                captions: captions,
                storyboards: storyboards,
                quality: downloadSettings.preferredDownloadQuality,
                includeSubtitles: downloadSettings.includeSubtitlesInAutoDownload
            )
        } catch {
            return .failure(code: "downloadFailed", message: error.localizedDescription)
        }
        return .success(values(for: video).merging(["status": "queued"]) { $1 })
        #endif
    }

    private func bookmark(_ url: URL) async -> LinkActionResult {
        let video: Video
        switch await resolve(url) {
        case .success(let resolved): video = resolved.0
        case .failure(let failure): return failure.result
        }
        let dataManager = appEnvironment.dataManager
        guard !dataManager.isBookmarked(videoID: video.id.videoID) else {
            return .success(values(for: video))
        }
        let confirmed = await confirm(
            title: String(localized: "linkAction.confirm.bookmark.title", defaultValue: "Add Bookmark?"),
            subject: video.title,
            detail: video.author.name,
            confirmTitle: String(localized: "linkAction.confirm.bookmark.button", defaultValue: "Bookmark"),
            systemImage: "bookmark"
        )
        guard confirmed else { return .cancelled }

        dataManager.addBookmark(for: video)
        appEnvironment.toastManager.showSuccess(
            String(localized: "linkAction.done.bookmark", defaultValue: "Bookmarked"),
            subtitle: video.title
        )
        return .success(values(for: video))
    }

    // MARK: - Subscriptions

    private func setSubscribed(_ subscribe: Bool, channelURL url: URL) async -> LinkActionResult {
        guard case .channel(let channelID, let source) = URLRouter().route(url) else {
            return .failure(code: "notAChannel", message: String(localized: "linkAction.error.notAChannel", defaultValue: "The link isn't a channel."))
        }
        guard let instance = appEnvironment.instancesManager.instance(for: source) else {
            return LinkActionFailure.noSource.result
        }

        let channel: Channel
        do {
            // Resolves @handles and custom URLs to the channel's real ID
            channel = try await appEnvironment.contentService.channel(id: channelID, instance: instance)
        } catch {
            return .failure(code: "loadFailed", message: error.localizedDescription)
        }

        let service = appEnvironment.subscriptionService
        let values = ["channelID": channel.id.channelID, "channel": channel.name]
        if await service.isSubscribed(to: channel.id.channelID) == subscribe {
            return .success(values)
        }

        let confirmed = await confirm(
            title: subscribe
                ? String(localized: "linkAction.confirm.subscribe.title", defaultValue: "Subscribe?")
                : String(localized: "linkAction.confirm.unsubscribe.title", defaultValue: "Unsubscribe?"),
            subject: channel.name,
            detail: nil,
            confirmTitle: subscribe
                ? String(localized: "linkAction.confirm.subscribe.button", defaultValue: "Subscribe")
                : String(localized: "linkAction.confirm.unsubscribe.button", defaultValue: "Unsubscribe"),
            systemImage: subscribe ? "person.badge.plus" : "person.badge.minus"
        )
        guard confirmed else { return .cancelled }

        do {
            if subscribe {
                try await service.subscribe(to: channel)
                if appEnvironment.settingsManager.defaultNotificationsForNewChannels {
                    appEnvironment.dataManager.setNotificationsEnabled(true, for: channel.id.channelID)
                }
            } else {
                try await service.unsubscribe(from: channel.id.channelID)
            }
        } catch {
            return .failure(code: subscribe ? "subscribeFailed" : "unsubscribeFailed", message: error.localizedDescription)
        }
        appEnvironment.toastManager.showSuccess(
            subscribe
                ? String(localized: "linkAction.done.subscribe", defaultValue: "Subscribed")
                : String(localized: "linkAction.done.unsubscribe", defaultValue: "Unsubscribed"),
            subtitle: channel.name
        )
        return .success(values)
    }

    // MARK: - Player Commands

    private func perform(_ command: LinkAction.PlayerCommand) async -> LinkActionResult {
        let player = appEnvironment.playerService
        if case .state = command {
            return .success(playerValues())
        }
        guard player.state.currentVideo != nil else {
            return .failure(code: "nothingPlaying", message: String(localized: "linkAction.error.nothingPlaying", defaultValue: "Nothing is playing."))
        }

        switch command {
        case .play:
            player.resume()
        case .pause:
            player.pause()
        case .toggle:
            player.togglePlayPause()
        case .next:
            await player.playNext()
        case .previous:
            await player.playPrevious()
        case .close:
            appEnvironment.navigationCoordinator.isPlayerExpanded = false
            player.stop()
            return .success()
        case .state:
            break
        case .seek(let time):
            await player.seek(to: clampedTime(time))
        case .seekBy(let delta):
            await player.seek(to: clampedTime(player.state.currentTime + delta))
        case .rate(let value):
            guard let rate = PlaybackRate(rawValue: value) else {
                let supported = PlaybackRate.allCases.map { String($0.rawValue) }.joined(separator: ", ")
                return .failure(code: "unsupportedRate", message: String(localized: "linkAction.error.unsupportedRate", defaultValue: "Supported rates: \(supported)"))
            }
            player.currentBackend?.rate = Float(rate.rawValue)
            player.state.rate = rate
        }
        return .success(playerValues())
    }

    private func clampedTime(_ time: TimeInterval) -> TimeInterval {
        let duration = appEnvironment.playerService.state.duration
        let upper = duration > 0 ? duration : time
        return min(max(time, 0), upper)
    }

    // MARK: - Helpers

    private enum LinkActionFailure: Error {
        case noSource
        case notAVideo(String)
        case loadFailed(String)

        var result: LinkActionResult {
            switch self {
            case .noSource:
                return .failure(code: "noSource", message: String(localized: "deepLink.noInstance.subtitle", defaultValue: "No source is configured for this video."))
            case .notAVideo(let message):
                return .failure(code: "notAVideo", message: message)
            case .loadFailed(let message):
                return .failure(code: "loadFailed", message: message)
            }
        }
    }

    /// Loads the video a link points at, showing progress while it does.
    private func resolve(_ url: URL) async -> Result<(Video, [Stream], [Caption], [Storyboard]), LinkActionFailure> {
        let toastID = appEnvironment.toastManager.show(
            scopes: [.main, .player],
            category: .loading,
            title: String(localized: "deepLink.loading.title", defaultValue: "Loading video…"),
            autoDismissDelay: 30.0
        )
        defer { appEnvironment.toastManager.dismiss(id: toastID) }

        do {
            return .success(try await LinkVideoResolver(appEnvironment: appEnvironment).resolve(url))
        } catch let error as LinkResolveError {
            switch error {
            case .noInstanceAvailable: return .failure(.noSource)
            case .noYatteeServer, .notAVideo: return .failure(.notAVideo(error.localizedDescription))
            }
        } catch {
            return .failure(.loadFailed(error.localizedDescription))
        }
    }

    /// Asks first unless the user lets automation links change things on their own.
    private func confirm(title: String, subject: String?, detail: String?, confirmTitle: String, systemImage: String) async -> Bool {
        guard !appEnvironment.settingsManager.linkActionsRunWithoutConfirmation else { return true }
        let confirmation = LinkActionConfirmation(
            title: title,
            subject: subject,
            detail: detail,
            confirmTitle: confirmTitle,
            systemImage: systemImage
        )
        return await confirmation.ask(using: appEnvironment.navigationCoordinator.presenter)
    }

    private func values(for video: Video) -> [String: String] {
        ["videoID": video.id.videoID, "title": video.title, "channel": video.author.name]
    }

    private func playerValues() -> [String: String] {
        let state = appEnvironment.playerService.state
        guard let video = state.currentVideo else { return ["playing": "false"] }
        var values = values(for: video)
        values["playing"] = String(state.playbackState == .playing)
        values["position"] = String(Int(state.currentTime))
        values["duration"] = String(Int(state.duration))
        values["rate"] = String(state.rate.rawValue)
        return values
    }

    /// Failures show a toast; callers that report back get the same message.
    private func report(_ result: LinkActionResult) {
        guard case .failure(let code, let message) = result else { return }
        LoggingService.shared.warning("Link action failed: \(code) — \(message)", category: .general)
        appEnvironment.toastManager.showError(
            String(localized: "linkAction.error.title", defaultValue: "Couldn't complete the link"),
            subtitle: message
        )
    }
}
