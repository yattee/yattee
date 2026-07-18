//
//  ExternalVideoView.swift
//  Yattee
//
//  Loading view for extracting and playing external site videos via Yattee Server.
//

import SwiftUI

/// View for extracting and playing videos from external sites (non-YouTube/PeerTube).
/// Uses Yattee Server's yt-dlp integration to extract video information.
struct ExternalVideoView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    let url: URL

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shouldDismissWhenPlayerExpands = false

    var body: some View {
        Group {
            if isLoading {
                LoadingView(
                    message: String(localized: "externalVideo.extracting"),
                    subtext: url.host ?? url.absoluteString
                )
            } else if let error = errorMessage {
                ErrorStateView(
                    title: String(localized: "externalVideo.couldNotExtract"),
                    message: error,
                    onRetry: { await extractAndPlay() },
                    onDismiss: { dismiss() }
                )
            }
            // On success, view dismisses after player expands
        }
        .task {
            await extractAndPlay()
        }
        .onChange(of: appEnvironment?.navigationCoordinator.isPlayerExpanded) { _, isExpanded in
            // Dismiss this view after the player has expanded
            if isExpanded == true && shouldDismissWhenPlayerExpands {
                dismiss()
            }
        }
    }

    // MARK: - Extraction

    private func extractAndPlay() async {
        guard let appEnvironment else {
            errorMessage = String(localized: "externalVideo.appNotReady")
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        // Find a Yattee Server instance
        guard let instance = appEnvironment.instancesManager.yatteeServerInstance else {
            errorMessage = String(localized: "externalVideo.noYatteeServer")
            isLoading = false
            return
        }

        do {
            let (video, _, _) = try await appEnvironment.contentService.extractURL(url, instance: instance)

            // Play the video - view will dismiss when player expands
            await MainActor.run {
                // Set flag to dismiss when player expands
                shouldDismissWhenPlayerExpands = true

                // Don't pass a specific stream - let the player's selectStreamAndBackend
                // choose the best video+audio combination. Using streams.first would
                // incorrectly select audio-only streams for sites like Bilibili.
                appEnvironment.playerService.openVideo(video)
            }

        } catch let error as APIError {
            isLoading = false
            switch error {
            case .httpError(let statusCode, let message):
                if statusCode == 422 {
                    errorMessage = message ?? String(localized: "externalVideo.error.unsupported")
                } else if statusCode == 400 {
                    errorMessage = message ?? String(localized: "externalVideo.error.invalidUrl")
                } else {
                    errorMessage = message ?? String(localized: "externalVideo.error.server \(statusCode)")
                }
            case .decodingError:
                errorMessage = String(localized: "externalVideo.error.parsing")
            case .noConnection:
                errorMessage = String(localized: "externalVideo.error.noConnection")
            case .timeout:
                errorMessage = String(localized: "externalVideo.error.timeout")
            default:
                errorMessage = error.localizedDescription
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - InstancesManager Extension

extension InstancesManager {
    /// Returns the first enabled Yattee Server instance, if any.
    var yatteeServerInstance: Instance? {
        instances.first { $0.type == .yatteeServer && $0.isEnabled }
    }
}

#Preview {
    ExternalVideoView(url: URL(string: "https://vimeo.com/123456")!)
}
