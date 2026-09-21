//
//  TracksPanelPage.swift
//  Yattee
//
//  Details panel page embedding the quality/audio/subtitles/rate selector.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct TracksPanelPage: View {
    let context: PanelPageContext
    var bottomInset: CGFloat = 0

    private var appEnvironment: AppEnvironment? { context.appEnvironment }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }

    var body: some View {
        if let playerService {
            let supportedFormats = playerService.currentBackendType.supportedFormats
            QualitySelectorView(
                streams: playerService.availableStreams.filter { stream in
                    let format = StreamFormat.detect(from: stream)
                    // DASH is never offered for manual selection
                    if format == .dash {
                        return false
                    }
                    return supportedFormats.contains(format)
                },
                captions: playerService.availableCaptions,
                currentStream: playerState?.currentStream,
                currentAudioStream: playerState?.currentAudioStream,
                currentCaption: playerService.currentCaption,
                isLoading: playerService.availableStreams.isEmpty && playerState?.playbackState == .loading,
                currentDownload: playerService.currentDownload,
                isLoadingOnlineStreams: playerService.isLoadingOnlineStreams,
                localCaptionURL: playerService.currentDownload.flatMap { download in
                    guard let path = download.localCaptionPath else { return nil }
                    return appEnvironment?.downloadManager.downloadsDirectory().appendingPathComponent(path)
                },
                currentRate: playerState?.rate ?? .x1,
                isControlsLocked: playerState?.isControlsLocked ?? false,
                isAudioMode: appEnvironment?.settingsManager.audioOnlyModeEnabled ?? false,
                embeddedAudioTracks: playerService.embeddedAudioTracks,
                embeddedSubtitleTracks: playerService.embeddedSubtitleTracks,
                currentEmbeddedAudioTrackID: playerService.selectedEmbeddedAudioTrackID,
                currentEmbeddedSubtitleTrackID: playerService.selectedEmbeddedSubtitleTrackID,
                embeddedVideoTrack: playerService.primaryEmbeddedVideoTrack,
                onStreamSelected: { stream, audioStream in
                    Task {
                        await playerService.selectStreamManually(stream, audioStream: audioStream)
                    }
                },
                onCaptionSelected: { caption in
                    playerService.loadCaption(caption)
                },
                onLoadOnlineStreams: {
                    Task {
                        await playerService.loadOnlineStreams()
                    }
                },
                onSwitchToOnlineStream: { stream, audioStream in
                    Task {
                        await playerService.switchToOnlineStream(stream, audioStream: audioStream)
                    }
                },
                onEmbeddedAudioTrackSelected: { trackID in
                    playerService.selectEmbeddedAudioTrack(trackID)
                },
                onEmbeddedSubtitleTrackSelected: { trackID in
                    playerService.selectEmbeddedSubtitleTrack(trackID)
                },
                onRateChanged: { rate in
                    playerState?.rate = rate
                    playerService.currentBackend?.rate = Float(rate.rawValue)
                },
                onLockToggled: { locked in
                    playerState?.isControlsLocked = locked
                },
                onAudioModeToggled: { enabled in
                    Task {
                        await playerService.setAudioMode(enabled)
                    }
                },
                isEmbedded: true
            )
            .safeAreaPadding(.bottom, bottomInset)
        }
    }
}

#endif
