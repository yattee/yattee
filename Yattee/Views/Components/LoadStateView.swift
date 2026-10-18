//
//  LoadStateView.swift
//  Yattee
//
//  Reusable components for loading, error, and empty states.
//

import SwiftUI

// MARK: - Loading View

/// A simple loading indicator with optional message and subtext.
struct LoadingView: View {
    var message: String? = nil
    var subtext: String? = nil
    /// tvOS: offered as a Cancel button once loading has taken a while.
    var onCancel: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            if let message {
                Text(message)
                    .font(.headline)
            }

            if let subtext {
                Text(subtext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal)
            }

            #if os(tvOS)
            if let onCancel {
                TVStalledLoadCancelButton(action: onCancel)
                    .padding(.top, 24)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(tvOS)
// MARK: - Stalled Load Cancel

/// A Cancel button that appears under a tvOS loading spinner once the load has
/// taken a while.
///
/// A screen showing only a spinner has nothing focusable: the focus engine has
/// nowhere to land, the remote cannot reach the sidebar and Menu cannot pop the
/// screen, so a hung request strands the user until it times out. Delayed so
/// a normal load never flashes the button.
struct TVStalledLoadCancelButton: View {
    var delay: Duration = .seconds(3)
    let action: () -> Void

    @State private var isShown = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if isShown {
                Button(String(localized: "common.cancel"), action: action)
                    .focused($isFocused)
            }
        }
        .task {
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            isShown = true
            // Focus was already lost by the time the button appears, and the
            // focus engine is not guaranteed to pick up a late arrival.
            guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
            isFocused = true
        }
    }
}

extension View {
    /// Puts a delayed Cancel under a tvOS loading spinner. See
    /// `TVStalledLoadCancelButton`.
    func tvStalledLoadCancel(action: @escaping () -> Void) -> some View {
        VStack(spacing: 40) {
            self
            TVStalledLoadCancelButton(action: action)
        }
    }
}
#endif

// MARK: - Error State View

/// An error view with icon, message, and action buttons.
struct ErrorStateView: View {
    let title: String
    let message: String
    var onRetry: (() async -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    var retryTitle: String = "Try Again"
    var dismissTitle: String = "Cancel"

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.yellow)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                if let onRetry {
                    Button(retryTitle) {
                        Task { await onRetry() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let onDismiss {
                    Button(dismissTitle) {
                        onDismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Loading") {
    LoadingView(message: "Loading video...", subtext: "youtube.com")
}

#Preview("Error") {
    ErrorStateView(
        title: "Could not load video",
        message: "The video is unavailable or has been removed.",
        onRetry: { try? await Task.sleep(for: .seconds(1)) },
        onDismiss: {}
    )
}
