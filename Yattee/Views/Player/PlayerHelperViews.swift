//
//  PlayerHelperViews.swift
//  Yattee
//
//  Helper views and types for the player sheet.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS)

// MARK: - Playback Info

/// Holds computed playback state flags to avoid duplicating these checks
struct PlaybackInfo {
    let state: PlaybackState
    let isLoading: Bool
    let isIdle: Bool
    let isEnded: Bool
    let isFailed: Bool
    let hasBackend: Bool
}

// MARK: - Compact Label

/// A compact label with an icon and text.
struct CompactLabel: View {
    let text: String
    let systemImage: String
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: systemImage)
            Text(text)
        }
    }
}

// MARK: - Loading Overlay View

/// An overlay view shown while video is loading.
struct LoadingOverlayView: View {
    /// Buffer progress percentage (0-100), nil shows indeterminate spinner.
    var bufferProgress: Int?

    var body: some View {
        Color.black.opacity(0.4)
        VStack(spacing: 12) {
            if let progress = bufferProgress, progress < 100 {
                // Circular progress indicator showing buffer percentage
                CircularBufferProgress(progress: progress)
            } else {
                // Indeterminate spinner
                ProgressView()
                    .tint(.white)
                    .controlSize(.large)
            }
        }
    }
}

/// Circular progress view showing buffer percentage.
struct CircularBufferProgress: View {
    let progress: Int

    private var progressValue: Double {
        Double(progress) / 100.0
    }

    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 4)
                .frame(width: 44, height: 44)

            // Progress arc
            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 44, height: 44)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progressValue)
        }
    }
}

// MARK: - Error Details Sheet

/// Sheet displaying error details with copy/share options.
struct ErrorDetailsSheet: View {
    let errorMessage: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Error message
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle(String(localized: "player.error.details.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    // Copy button
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(String(localized: "player.error.copy"), systemImage: "doc.on.doc")
                    }
                    .accessibilityLabel(String(localized: "player.error.copy.accessibilityLabel"))

                    #if os(iOS) || os(macOS)
                    // Share button (not available on tvOS)
                    ShareLink(item: errorMessage) {
                        Label(String(localized: "player.error.share"), systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel(String(localized: "player.error.share.accessibilityLabel"))
                    #endif
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    private func copyToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = errorMessage
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(errorMessage, forType: .string)
        #endif
    }
}

// MARK: - Player Overlay Button

/// A circular glass button used for player overlays (play, replay, retry, etc.)
struct PlayerOverlayButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 70, height: 70)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .environment(\.colorScheme, .dark)
        } else {
            Button(action: action) {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Image(systemName: icon)
                            .font(.title)
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(.plain)
        }
    }
}

#endif
