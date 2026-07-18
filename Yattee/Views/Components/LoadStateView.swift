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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

// MARK: - Load State View (Generic Container)

/// A generic container that handles loading, error, and content states.
///
/// Example usage:
/// ```swift
/// LoadStateView(
///     isLoading: viewModel.isLoading,
///     errorMessage: viewModel.error,
///     data: viewModel.data,
///     loadingMessage: "Loading...",
///     errorTitle: "Error",
///     onRetry: { await viewModel.load() }
/// ) { data in
///     ContentView(data: data)
/// }
/// ```
struct LoadStateView<Content: View, Data>: View {
    let isLoading: Bool
    let errorMessage: String?
    let data: Data?
    var loadingMessage: String? = nil
    var loadingSubtext: String? = nil
    var errorTitle: String = "Error"
    var onRetry: (() async -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    @ViewBuilder let content: (Data) -> Content

    var body: some View {
        Group {
            if isLoading && data == nil {
                LoadingView(message: loadingMessage, subtext: loadingSubtext)
            } else if let error = errorMessage, data == nil {
                ErrorStateView(
                    title: errorTitle,
                    message: error,
                    onRetry: onRetry,
                    onDismiss: onDismiss
                )
            } else if let data {
                content(data)
            }
        }
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

#Preview("LoadStateView - Loading") {
    LoadStateView(
        isLoading: true,
        errorMessage: nil,
        data: nil as String?,
        loadingMessage: "Fetching data..."
    ) { data in
        Text(data)
    }
}

#Preview("LoadStateView - Error") {
    LoadStateView(
        isLoading: false,
        errorMessage: "Network error occurred",
        data: nil as String?,
        errorTitle: "Failed to Load",
        onRetry: {}
    ) { data in
        Text(data)
    }
}

#Preview("LoadStateView - Content") {
    LoadStateView(
        isLoading: false,
        errorMessage: nil,
        data: "Hello, World!",
        loadingMessage: "Loading..."
    ) { data in
        Text(data)
            .font(.largeTitle)
    }
}
