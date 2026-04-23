//
//  TapZonePreview.swift
//  Yattee
//
//  Interactive preview showing tap zones that can be tapped to configure.
//

import SwiftUI

/// Interactive preview of tap zones. Tapping a zone opens its configuration.
struct TapZonePreview: View {
    let layout: TapZoneLayout
    let configurations: [TapZoneConfiguration]
    let onZoneTapped: (TapZonePosition) -> Void

    @State private var tappedZone: TapZonePosition?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black)

                // Zone overlays
                switch layout {
                case .single:
                    singleLayout(size: geometry.size)
                case .horizontalSplit:
                    horizontalSplitLayout(size: geometry.size)
                case .verticalSplit:
                    verticalSplitLayout(size: geometry.size)
                case .threeColumns:
                    threeColumnsLayout(size: geometry.size)
                case .quadrants:
                    quadrantsLayout(size: geometry.size)
                }
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Layouts

    @ViewBuilder
    private func singleLayout(size: CGSize) -> some View {
        zoneButton(
            position: .full,
            frame: CGRect(origin: .zero, size: size)
        )
    }

    @ViewBuilder
    private func horizontalSplitLayout(size: CGSize) -> some View {
        HStack(spacing: 2) {
            zoneButton(position: .left)
            zoneButton(position: .right)
        }
        .padding(2)
    }

    @ViewBuilder
    private func verticalSplitLayout(size: CGSize) -> some View {
        VStack(spacing: 2) {
            zoneButton(position: .top)
            zoneButton(position: .bottom)
        }
        .padding(2)
    }

    @ViewBuilder
    private func threeColumnsLayout(size: CGSize) -> some View {
        HStack(spacing: 2) {
            zoneButton(position: .leftThird)
            zoneButton(position: .center)
            zoneButton(position: .rightThird)
        }
        .padding(2)
    }

    @ViewBuilder
    private func quadrantsLayout(size: CGSize) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                zoneButton(position: .topLeft)
                zoneButton(position: .topRight)
            }
            HStack(spacing: 2) {
                zoneButton(position: .bottomLeft)
                zoneButton(position: .bottomRight)
            }
        }
        .padding(2)
    }

    // MARK: - Zone Button

    @ViewBuilder
    private func zoneButton(
        position: TapZonePosition,
        frame: CGRect? = nil
    ) -> some View {
        let config = configurations.first { $0.position == position }
        let action = config?.action

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                tappedZone = position
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tappedZone = nil
                }
                onZoneTapped(position)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(tappedZone == position ? 0.3 : 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    if let action {
                        Image(systemName: action.systemImage)
                            .font(.title2)
                            .foregroundStyle(.white)

                        Text(actionLabel(for: action))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Image(systemName: "questionmark")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.5))

                        Text(position.displayName)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(8)
            }
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(for action: TapGestureAction) -> String {
        switch action {
        case .seekForward(let seconds):
            "+\(seconds)s"
        case .seekBackward(let seconds):
            "-\(seconds)s"
        case .togglePlayPause:
            "Play/Pause"
        case .toggleFullscreen:
            "Fullscreen"
        case .togglePiP:
            "PiP"
        case .playNext:
            "Next"
        case .playPrevious:
            "Previous"
        case .cyclePlaybackSpeed:
            "Speed"
        case .toggleMute:
            "Mute"
        }
    }
}

#Preview {
    Form {
        Section {
            TapZonePreview(
                layout: .quadrants,
                configurations: [
                    TapZoneConfiguration(position: .topLeft, action: .seekBackward(seconds: 10)),
                    TapZoneConfiguration(position: .topRight, action: .seekForward(seconds: 10)),
                    TapZoneConfiguration(position: .bottomLeft, action: .playPrevious),
                    TapZoneConfiguration(position: .bottomRight, action: .playNext)
                ],
                onZoneTapped: { _ in }
            )
        }
    }
}
