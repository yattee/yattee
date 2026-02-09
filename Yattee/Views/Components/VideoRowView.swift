//
//  VideoRowView.swift
//  Yattee
//
//  A video row for list layouts.
//

import SwiftUI

/// A video row for list layouts.
///
/// Automatically handles DeArrow integration for titles and thumbnails.
/// Download status is automatically shown from the download manager.
/// On iOS/macOS, supports configurable tap zones for thumbnail and text area.
struct VideoRowView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.videoQueueContext) private var videoQueueContext

    let video: Video
    var style: VideoRowStyle = .regular
    var watchProgress: Double? = nil
    var showSourceBadge: Bool = false
    /// Custom metadata text to show instead of views/date (e.g., remaining time).
    var customMetadata: String? = nil
    /// Optional index number to display before thumbnail (for playlists).
    var index: Int? = nil
    /// When true, disables internal tap handling so parent view can handle all taps.
    var disableInternalTapHandling: Bool = false

    // Platform-specific fonts
    #if os(tvOS)
    private var titleFont: Font {
        style == .compact ? .caption : .body
    }
    private var authorFont: Font {
        style == .compact ? .caption2 : .subheadline
    }
    private var metadataFont: Font {
        style == .compact ? .caption2 : .caption
    }
    #else
    private var titleFont: Font {
        .subheadline
    }
    private var authorFont: Font {
        style == .compact ? .caption2 : .caption
    }
    private var metadataFont: Font {
        style == .compact ? .caption2 : .caption2
    }
    #endif
    
    #if !os(tvOS)
    private var thumbnailTapAction: VideoTapAction {
        appEnvironment?.settingsManager.thumbnailTapAction ?? .playVideo
    }
    
    private var textAreaTapAction: VideoTapAction {
        appEnvironment?.settingsManager.textAreaTapAction ?? .openInfo
    }
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Index number (for playlists)
            if let index {
                Text("\(index)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
            }
            
            // Thumbnail
            thumbnailView
                .zoomTransitionSource(id: video.id)

            // Info
            infoView
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("video.row.\(video.id.videoID)")
        .accessibilityLabel("video.row.\(video.id.videoID)")
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        DeArrowVideoThumbnail(
            video: video,
            cornerRadius: style == .compact ? 4 : style == .regular ? 6 : 8,
            watchProgress: watchProgress,
            duration: style == .compact ? nil : video.formattedDuration
        )
        .frame(width: style.thumbnailWidth, height: style.thumbnailHeight)
        #if !os(tvOS)
        .contentShape(Rectangle())
        .if(thumbnailTapAction != .playVideo && !disableInternalTapHandling) { view in
            view.highPriorityGesture(
                TapGesture().onEnded {
                    handleTapAction(thumbnailTapAction)
                }
            )
        }
        #endif
    }
    
    @ViewBuilder
    private var infoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                .font(titleFont)
                .lineLimit(style == .large ? 3 : style == .regular ? 2 : 1)

            HStack(spacing: 4) {
                if style == .compact {
                    // In compact mode, show author and duration inline with dot separator
                    let duration = video.formattedDuration
                    if !duration.isEmpty {
                        Text("\(video.author.name) · \(duration)")
                            .font(authorFont)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(video.author.name)
                            .font(authorFont)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(video.author.name)
                        .font(authorFont)
                        .foregroundStyle(.secondary)
                }
                
                if showSourceBadge {
                    SourceBadge(source: video.id.source)
                }
            }

            if style != .compact {
                if let custom = customMetadata {
                    Text(custom)
                        .font(metadataFont)
                        .foregroundStyle(.tertiary)
                } else if video.viewCount != nil || video.formattedPublishedDate != nil {
                    VideoMetadataLine(viewCount: video.formattedViewCount, publishedText: video.formattedPublishedDate)
                        .font(metadataFont)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(tvOS)
        .contentShape(Rectangle())
        .if(textAreaTapAction != .playVideo && !disableInternalTapHandling) { view in
            view.highPriorityGesture(
                TapGesture().onEnded {
                    handleTapAction(textAreaTapAction)
                }
            )
        }
        #endif
    }
    
    #if !os(tvOS)
    private func handleTapAction(_ action: VideoTapAction) {
        guard let env = appEnvironment else { return }
        
        switch action {
        case .playVideo:
            // This should not be called since we only add gesture for non-playVideo actions
            // The .tappableVideo() modifier will handle playVideo actions
            break
        case .openInfo:
            env.navigationCoordinator.navigate(to: .video(.loaded(video), queueContext: videoQueueContext))
        case .none:
            break
        }
    }
    #endif
}

// MARK: - Preview

#Preview("Row") {
    VideoRowView(
        video: .preview,
        watchProgress: 0.6,
        showSourceBadge: true
    )
    .padding()
}
