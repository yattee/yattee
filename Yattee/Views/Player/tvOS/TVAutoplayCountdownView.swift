//
//  TVAutoplayCountdownView.swift
//  Yattee
//
//  Autoplay countdown overlay for tvOS - shows countdown and next video preview.
//

#if os(tvOS)
import SwiftUI
import NukeUI

/// Autoplay countdown overlay for tvOS player.
/// Shows countdown timer and next video preview with options to play immediately or cancel.
struct TVAutoplayCountdownView: View {
    let countdown: Int
    let nextVideo: QueuedVideo
    let onPlayNext: () -> Void
    let onCancel: () -> Void
    
    @FocusState private var focusedButton: CountdownButton?
    
    enum CountdownButton: Hashable {
        case playNext
        case cancel
    }
    
    var body: some View {
        ZStack {
            // Dark overlay background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Countdown text
                Text(String(localized: "player.autoplay.playingIn \(countdown)"))
                    .font(.system(size: 48, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                
                // Next video preview card
                nextVideoCard
                    .focusable()
                    .scaleEffect(focusedButton == nil ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: focusedButton)
                
                // Action buttons
                HStack(spacing: 40) {
                    playNextButton
                    cancelButton
                }
                .focusSection()
            }
        }
        .onAppear {
            // Set default focus to Play Next
            focusedButton = .playNext
        }
    }
    
    // MARK: - Next Video Card
    
    private var nextVideoCard: some View {
        HStack(spacing: 20) {
            // Thumbnail
            LazyImage(url: nextVideo.video.bestThumbnail?.url) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 280, height: 158)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Video info
            VStack(alignment: .leading, spacing: 8) {
                Text(nextVideo.video.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Text(nextVideo.video.author.name)
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                
                // Duration badge if available
                if nextVideo.video.duration > 0 {
                    Text(formatDuration(nextVideo.video.duration))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.white.opacity(0.2))
                        )
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
        }
        .padding(20)
        .frame(width: 720)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.1))
        )
    }
    
    // MARK: - Buttons
    
    private var playNextButton: some View {
        Button {
            onPlayNext()
        } label: {
            Text(String(localized: "player.autoplay.playNext"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 250, height: 80)
        }
        .buttonStyle(TVCountdownButtonStyle())
        .focused($focusedButton, equals: .playNext)
    }
    
    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Text(String(localized: "player.autoplay.cancel"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 250, height: 80)
        }
        .buttonStyle(TVCountdownButtonStyle())
        .focused($focusedButton, equals: .cancel)
    }
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Button Style

/// Button style for countdown action buttons (Play Next, Cancel).
struct TVCountdownButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? .white.opacity(0.3) : .white.opacity(0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.05 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#endif
