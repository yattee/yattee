//
//  SponsorBlockOverlay.swift
//  Yattee
//
//  Overlay showing SponsorBlock segment skip notification.
//

import SwiftUI

struct SponsorBlockOverlay: View {
    let segment: SponsorBlockSegment
    let onSkip: () async -> Void
    let onDismiss: () -> Void

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 12) {
            // Category indicator
            Circle()
                .fill(segment.category.overlayColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(segment.category.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(String(localized: "sponsorBlock.skipPrompt"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Skip button
            Button {
                Task { await onSkip() }
            } label: {
                Text(String(localized: "sponsorBlock.skip"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(segment.category.overlayColor)
                    .clipShape(Capsule())
            }

            // Dismiss button
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .scaleEffect(isAnimating ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Category Color Extension

extension SponsorBlockCategory {
    var overlayColor: Color {
        switch self {
        case .sponsor:
            return .green
        case .selfpromo:
            return .yellow
        case .interaction:
            return .purple
        case .intro:
            return .cyan
        case .outro:
            return .blue
        case .preview:
            return .indigo
        case .filler:
            return .gray
        case .musicOfftopic:
            return .orange
        case .highlight:
            return .pink
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.opacity(0.8)

        VStack {
            Spacer()

            SponsorBlockOverlay(
                segment: SponsorBlockSegment(
                    uuid: "test",
                    category: .sponsor,
                    actionType: .skip,
                    segment: [30.0, 60.0],
                    videoDuration: 180.0,
                    locked: nil,
                    votes: nil,
                    segmentDescription: nil
                ),
                onSkip: {},
                onDismiss: {}
            )
        }
    }
}
