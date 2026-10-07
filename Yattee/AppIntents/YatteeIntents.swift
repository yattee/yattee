//
//  YatteeIntents.swift
//  Yattee
//
//  Shortcuts and Siri actions. Each runs the same `LinkAction` as the matching
//  yattee:// link, without the confirmation sheet: the person built the
//  shortcut, so no web page can trigger it behind their back.
//
//  Intent type names, AppEnum raw values and App Shortcut phrases are stored
//  in people's shortcuts: add new ones, never rename or remove shipped ones.
//

import AppIntents
import Foundation

// MARK: - Running Actions

/// A failure Shortcuts and Siri show with its own message.
enum YatteeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case failed(String)
    case unsupportedLink

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .failed(let message):
            return "\(message)"
        case .unsupportedLink:
            return "Yattee can only open web links."
        }
    }
}

extension LinkAction {
    /// Runs the action and returns its values, or throws its failure.
    @MainActor
    fileprivate func performFromIntent() async throws -> [String: String] {
        let result = await LinkActionPerformer(appEnvironment: .shared, asksBeforeChanges: false).perform(self)
        switch result {
        case .success(let values):
            return values
        case .failure(_, let message):
            throw YatteeIntentError.failed(message)
        case .cancelled:
            throw YatteeIntentError.failed(String(localized: "linkAction.error.title", defaultValue: "Couldn't complete the link"))
        }
    }
}

private func checkedLink(_ url: URL) throws -> URL {
    guard LinkActionParser.isAllowedTarget(url) else { throw YatteeIntentError.unsupportedLink }
    return url
}

// MARK: - Video Actions

struct PlayVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Video"
    static let description = IntentDescription("Plays a YouTube, PeerTube or direct media link in Yattee.")
    static let openAppWhenRun = true

    @Parameter(title: "Link")
    var link: URL

    @Parameter(title: "Start Time", description: "Seconds from the start. Leave empty to use the link's own time.")
    var startTime: Double?

    static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$link)") {
            \.$startTime
        }
    }

    func perform() async throws -> some ReturnsValue<String> {
        let link = try checkedLink(link)
        let start = startTime ?? URLRouter().parseTimestamp(link)
        let values = try await LinkAction.play(link, startTime: start).performFromIntent()
        return .result(value: values["title"] ?? "")
    }
}

enum QueuePosition: String, AppEnum {
    case next
    case end

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Queue Position"
    static let caseDisplayRepresentations: [QueuePosition: DisplayRepresentation] = [
        .next: "Play Next",
        .end: "End of Queue",
    ]
}

struct AddToQueueIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Video to Queue"
    static let description = IntentDescription("Adds a video to Yattee's queue, to play next or at the end.")

    @Parameter(title: "Link")
    var link: URL

    @Parameter(title: "Position", default: .end)
    var position: QueuePosition

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$link) to queue (\(\.$position))")
    }

    func perform() async throws -> some ReturnsValue<String> {
        let link = try checkedLink(link)
        let action: LinkAction = position == .next ? .playNext(link) : .addToQueue(link)
        let values = try await action.performFromIntent()
        return .result(value: values["title"] ?? "")
    }
}

#if !os(tvOS)
struct DownloadVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Download Video"
    static let description = IntentDescription("Downloads a video in Yattee at your preferred download quality.")
    // The quality picker may need to show
    static let openAppWhenRun = true

    @Parameter(title: "Link")
    var link: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Download \(\.$link)")
    }

    func perform() async throws -> some ReturnsValue<String> {
        let values = try await LinkAction.download(try checkedLink(link)).performFromIntent()
        return .result(value: values["title"] ?? "")
    }
}
#endif

struct BookmarkVideoIntent: AppIntent {
    static let title: LocalizedStringResource = "Bookmark Video"
    static let description = IntentDescription("Adds a video to your Yattee bookmarks.")

    @Parameter(title: "Link")
    var link: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Bookmark \(\.$link)")
    }

    func perform() async throws -> some ReturnsValue<String> {
        let values = try await LinkAction.bookmark(try checkedLink(link)).performFromIntent()
        return .result(value: values["title"] ?? "")
    }
}

// MARK: - Channel Actions

struct SubscribeToChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Subscribe to Channel"
    static let description = IntentDescription("Subscribes to a channel from its link, in the account you're using in Yattee.")

    @Parameter(title: "Channel Link")
    var link: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Subscribe to \(\.$link)")
    }

    func perform() async throws -> some ReturnsValue<String> {
        let values = try await LinkAction.subscribe(try checkedLink(link)).performFromIntent()
        return .result(value: values["channel"] ?? "")
    }
}

struct UnsubscribeFromChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Unsubscribe from Channel"
    static let description = IntentDescription("Unsubscribes from a channel, in the account you're using in Yattee.")

    @Parameter(title: "Channel Link")
    var link: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Unsubscribe from \(\.$link)")
    }

    func perform() async throws -> some ReturnsValue<String> {
        let values = try await LinkAction.unsubscribe(try checkedLink(link)).performFromIntent()
        return .result(value: values["channel"] ?? "")
    }
}

// MARK: - Player

enum PlayerControlCommand: String, AppEnum {
    case play
    case pause
    case toggle
    case next
    case previous
    case close

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Player Command"
    static let caseDisplayRepresentations: [PlayerControlCommand: DisplayRepresentation] = [
        // Synonyms are what Siri also accepts in "{command} in Yattee"
        .play: DisplayRepresentation(title: "Resume", synonyms: ["Play", "Continue", "Unpause"]),
        .pause: DisplayRepresentation(title: "Pause", synonyms: ["Stop"]),
        .toggle: DisplayRepresentation(title: "Play/Pause", synonyms: ["Play or Pause", "Toggle Playback"]),
        .next: DisplayRepresentation(title: "Next Video", synonyms: ["Next", "Skip", "Skip Video"]),
        .previous: DisplayRepresentation(title: "Previous Video", synonyms: ["Previous", "Go Back"]),
        .close: DisplayRepresentation(title: "Close Player", synonyms: ["Close", "Close Video"]),
    ]

    var command: LinkAction.PlayerCommand {
        switch self {
        case .play: .play
        case .pause: .pause
        case .toggle: .toggle
        case .next: .next
        case .previous: .previous
        case .close: .close
        }
    }
}

struct ControlPlayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Control Player"
    static let description = IntentDescription("Resumes, pauses, skips or closes what's playing in Yattee.")

    @Parameter(title: "Command", default: .toggle)
    var command: PlayerControlCommand

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$command) in Yattee")
    }

    func perform() async throws -> some IntentResult {
        _ = try await LinkAction.player(command.command).performFromIntent()
        return .result()
    }
}

enum SeekMode: String, AppEnum {
    case to
    case forward
    case backward

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Seek Mode"
    static let caseDisplayRepresentations: [SeekMode: DisplayRepresentation] = [
        .to: "To",
        .forward: "Forward By",
        .backward: "Back By",
    ]
}

struct SeekIntent: AppIntent {
    static let title: LocalizedStringResource = "Seek"
    static let description = IntentDescription("Jumps to a time in what's playing in Yattee, or forward or back by some seconds.")

    @Parameter(title: "Mode", default: .forward)
    var mode: SeekMode

    @Parameter(title: "Seconds", default: 10)
    var seconds: Double

    static var parameterSummary: some ParameterSummary {
        Summary("Seek \(\.$mode) \(\.$seconds) seconds")
    }

    func perform() async throws -> some IntentResult {
        let command: LinkAction.PlayerCommand = switch mode {
        case .to: .seek(to: max(seconds, 0))
        case .forward: .seekBy(abs(seconds))
        case .backward: .seekBy(-abs(seconds))
        }
        _ = try await LinkAction.player(command).performFromIntent()
        return .result()
    }
}

enum PlaybackSpeed: String, AppEnum {
    case x025 = "0.25"
    case x05 = "0.5"
    case x075 = "0.75"
    case x1 = "1"
    case x125 = "1.25"
    case x15 = "1.5"
    case x175 = "1.75"
    case x2 = "2"
    case x25 = "2.5"
    case x3 = "3"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback Speed"
    static let caseDisplayRepresentations: [PlaybackSpeed: DisplayRepresentation] = [
        .x025: "0.25×",
        .x05: "0.5×",
        .x075: "0.75×",
        .x1: "Normal",
        .x125: "1.25×",
        .x15: "1.5×",
        .x175: "1.75×",
        .x2: "2×",
        .x25: "2.5×",
        .x3: "3×",
    ]
}

struct SetPlaybackSpeedIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Playback Speed"
    static let description = IntentDescription("Changes the speed of what's playing in Yattee.")

    @Parameter(title: "Speed", default: .x1)
    var speed: PlaybackSpeed

    static var parameterSummary: some ParameterSummary {
        Summary("Set playback speed to \(\.$speed)")
    }

    func perform() async throws -> some IntentResult {
        _ = try await LinkAction.player(.rate(Double(speed.rawValue) ?? 1)).performFromIntent()
        return .result()
    }
}

struct GetNowPlayingIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Now Playing"
    static let description = IntentDescription("Returns the title of what's playing in Yattee, or nothing when the player is closed.")

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let values = try await LinkAction.player(.state).performFromIntent()
        guard let title = values["title"] else {
            return .result(value: "", dialog: "Nothing is playing in Yattee.")
        }
        return .result(value: title, dialog: "\(title)")
    }
}

// MARK: - Navigation

enum YatteeSection: String, AppEnum {
    case home
    case subscriptions
    case bookmarks
    case history
    case playlists
    case continueWatching
    case downloads
    case settings

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static let caseDisplayRepresentations: [YatteeSection: DisplayRepresentation] = [
        .home: "Home",
        .subscriptions: DisplayRepresentation(title: "Subscriptions", synonyms: ["Feed", "Subscription Feed"]),
        .bookmarks: DisplayRepresentation(title: "Bookmarks", synonyms: ["Saved Videos"]),
        .history: DisplayRepresentation(title: "History", synonyms: ["Watch History"]),
        .playlists: "Playlists",
        .continueWatching: "Continue Watching",
        .downloads: "Downloads",
        .settings: "Settings",
    ]

    var destination: NavigationDestination? {
        switch self {
        case .home: nil
        case .subscriptions: .subscriptionsFeed
        case .bookmarks: .bookmarks
        case .history: .history
        case .playlists: .playlists
        case .continueWatching: .continueWatching
        case .downloads: .downloads
        case .settings: .settings
        }
    }
}

struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Section"
    static let description = IntentDescription("Opens a section of Yattee.")
    static let openAppWhenRun = true

    @Parameter(title: "Section", default: .subscriptions)
    var section: YatteeSection

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$section)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let coordinator = AppEnvironment.shared.navigationCoordinator
        coordinator.dismissPresentations()
        if let destination = section.destination {
            coordinator.navigate(to: destination)
        } else {
            coordinator.router.select(.home)
            coordinator.router.popToRoot(.home)
        }
        return .result()
    }
}

struct SearchVideosIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Videos"
    static let description = IntentDescription("Searches for videos in Yattee.")
    static let openAppWhenRun = true

    @Parameter(title: "Search For")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search Yattee for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let coordinator = AppEnvironment.shared.navigationCoordinator
        coordinator.dismissPresentations()
        coordinator.navigate(to: .search(query))
        return .result()
    }
}

// MARK: - Siri

struct YatteeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ControlPlayerIntent(),
            phrases: [
                "\(\.$command) in \(.applicationName)",
                "\(\.$command) \(.applicationName)",
            ],
            shortTitle: "Control Player",
            systemImageName: "playpause"
        )
        AppShortcut(
            intent: GetNowPlayingIntent(),
            phrases: [
                "What's playing in \(.applicationName)",
            ],
            shortTitle: "Now Playing",
            systemImageName: "play.rectangle"
        )
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
                "Show my \(\.$section) in \(.applicationName)",
            ],
            shortTitle: "Open Section",
            systemImageName: "square.grid.2x2"
        )
        AppShortcut(
            intent: SearchVideosIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search for videos in \(.applicationName)",
            ],
            shortTitle: "Search Videos",
            systemImageName: "magnifyingglass"
        )
    }
}
