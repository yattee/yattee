//
//  SourceBadge.swift
//  Yattee
//
//  Adaptive source indicator shown only when disambiguation is needed.
//

import SwiftUI

/// Shows source badge only when user has multiple sources configured.
struct SourceBadge: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let source: ContentSource

    var body: some View {
        if shouldShowBadge {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.caption2)
                if let label {
                    Text(label)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
        }
    }

    // MARK: - Logic

    private var shouldShowBadge: Bool {
        guard let instances = appEnvironment?.instancesManager else {
            return false
        }

        // Single network = no badges needed
        let hasYouTube = instances.hasYouTubeInstances
        let hasPeerTube = instances.hasPeerTubeInstances
        let peerTubeCount = instances.peertubeInstances.count

        // Only YouTube or only one PeerTube = no badge
        if hasYouTube && !hasPeerTube { return false }
        if !hasYouTube && peerTubeCount <= 1 { return false }

        // Multiple PeerTube instances = show instance names
        if peerTubeCount > 1, case .federated = source {
            return true
        }

        // Mixed networks = show all
        return hasYouTube && hasPeerTube
    }

    private var icon: String {
        switch source {
        case .global:
            return "play.rectangle"
        case .federated:
            return "server.rack"
        case .extracted:
            return "link"
        }
    }

    private var label: String? {
        guard let instances = appEnvironment?.instancesManager else {
            return nil
        }

        switch source {
        case .global:
            // Show "YouTube" only if mixing with PeerTube
            return instances.hasPeerTubeInstances ? "YT" : nil

        case .federated(_, let url):
            // Show hostname if multiple PT instances
            if instances.peertubeInstances.count > 1 {
                return url.host
            }
            // If only one PT but mixing with YouTube, show "PT"
            return instances.hasYouTubeInstances ? "PT" : nil

        case .extracted:
            // Show the extractor name (e.g., "Vimeo")
            return source.shortName
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        SourceBadge(source: .global(provider: ContentSource.youtubeProvider))
        SourceBadge(source: .federated(provider: ContentSource.peertubeProvider, instance: URL(string: "https://peertube.social")!))
    }
    .padding()
    .appEnvironment(.preview)
}
