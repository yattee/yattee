//
//  CornerPlayerLayout.swift
//  Yattee
//
//  Corner player layout for iPad/macOS: video in the top-left, a resizable
//  side column on the right, and an optional region below the video —
//  YouTube-style. Pages are assigned to regions in the preset's panel
//  settings; the layout resolver in ExpandedPlayerSheet falls back to the
//  stacked layout when the window is too narrow.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct CornerPlayerLayout<PlayerContent: View>: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let playerControlsLayout: PlayerControlsLayout

    /// Video + controls area builder, sized by the layout.
    @ViewBuilder let playerContent: (
        _ onTogglePanel: @escaping () -> Void,
        _ isPanelVisible: Bool,
        _ width: CGFloat,
        _ height: CGFloat
    ) -> PlayerContent

    let onChannelTap: (() -> Void)?

    // MARK: - Layout Constants

    /// Side column width bounds.
    static var minColumnWidth: CGFloat { 280 }
    static var maxColumnWidthCap: CGFloat { 560 }
    /// Minimum width kept for the video column.
    static var minVideoColumnWidth: CGFloat { 480 }
    /// Maximum fraction of the window height the video area may take when a
    /// below-video region needs space.
    static var maxVideoHeightFraction: CGFloat { 0.72 }

    // MARK: - State

    @State private var isPanelVisible = true
    @State private var columnWidth: CGFloat = SettingsManager.defaultCornerPanelColumnWidth
    @State private var primaryPage: PanelPageType = .related
    @State private var belowVideoPage: PanelPageType = .info
    @State private var isGrabberActive = false

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }
    private var video: Video? { playerState?.currentVideo }
    private var accentColor: Color { settingsManager?.resolvedAccentColor ?? .accentColor }

    private var panelSettings: PanelSettings {
        playerControlsLayout.effectivePanelSettings
    }

    /// Region emptiness is decided at the config level: runtime-empty pages
    /// (no chapters, no related yet) are hidden inside the panel content, not
    /// by collapsing regions — layout jumps during loading would be jarring.
    private var hasPrimaryRegion: Bool {
        !panelSettings.enabledPages(in: .primary).isEmpty
    }

    private var hasBelowVideoRegion: Bool {
        !panelSettings.enabledPages(in: .belowVideo).isEmpty
    }

    private var panelBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private func clampColumnWidth(_ width: CGFloat, availableWidth: CGFloat) -> CGFloat {
        let maxWidth = max(
            Self.minColumnWidth,
            min(Self.maxColumnWidthCap, availableWidth * 0.45, availableWidth - Self.minVideoColumnWidth)
        )
        return min(max(width, Self.minColumnWidth), maxWidth)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let height = max(1, geometry.size.height)

            let showsPrimary = isPanelVisible && hasPrimaryRegion
            let showsBelowVideo = isPanelVisible && hasBelowVideoRegion

            let effectiveColumnWidth = clampColumnWidth(columnWidth, availableWidth: width)
            // Grabber sits on the column's leading edge, inside the column background.
            let totalColumnWidth = effectiveColumnWidth + 20

            let videoWidth = showsPrimary ? max(1, width - totalColumnWidth) : width
            let videoHeight: CGFloat = {
                guard showsBelowVideo else { return height }
                let rawAspectRatio = playerState?.displayAspectRatio ?? (16.0 / 9.0)
                let aspectRatio = rawAspectRatio > 0 ? rawAspectRatio : (16.0 / 9.0)
                return max(1, min(videoWidth / aspectRatio, height * Self.maxVideoHeightFraction))
            }()

            ZStack {
                Color.black.ignoresSafeArea(.all)

                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        playerContent(
                            togglePanel,
                            isPanelVisible,
                            videoWidth,
                            videoHeight
                        )
                        .frame(width: videoWidth, height: videoHeight)
                        .clipped()

                        if showsBelowVideo, let video {
                            regionPanel(
                                region: .belowVideo,
                                selectedPage: $belowVideoPage,
                                video: video
                            )
                            .frame(width: videoWidth)
                            .frame(maxHeight: .infinity)
                        }
                    }

                    if showsPrimary, let video {
                        HStack(spacing: 0) {
                            PanelResizeGrabber(
                                panelWidth: $columnWidth,
                                minWidth: Self.minColumnWidth,
                                maxWidth: clampColumnWidth(.infinity, availableWidth: width),
                                panelSide: .right,
                                isPinned: true,
                                isDragActive: $isGrabberActive
                            )

                            regionPanel(
                                region: .primary,
                                selectedPage: $primaryPage,
                                video: video
                            )
                            .frame(width: effectiveColumnWidth)
                        }
                        .background(panelBackgroundColor.ignoresSafeArea(edges: .vertical))
                    }
                }
            }
            .onChange(of: width) { _, newWidth in
                // Re-clamp when the window shrinks (still above the corner
                // threshold — below it the resolver switches layouts).
                columnWidth = clampColumnWidth(columnWidth, availableWidth: newWidth)
            }
        }
        .onAppear {
            isPanelVisible = settingsManager?.landscapeDetailsPanelVisible ?? true
            if let savedWidth = settingsManager?.cornerPanelColumnWidth, savedWidth > 0 {
                columnWidth = savedWidth
            }
        }
        .onChange(of: columnWidth) { _, newWidth in
            settingsManager?.cornerPanelColumnWidth = newWidth
        }
        .onChange(of: settingsManager?.landscapeDetailsPanelVisible) { _, newValue in
            // External writes (preset default visibility, other layout hosts)
            // must reach the local state too.
            guard let newValue, newValue != isPanelVisible else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isPanelVisible = newValue
            }
        }
    }

    // MARK: - Region Panel

    @ViewBuilder
    private func regionPanel(
        region: PanelRegion,
        selectedPage: Binding<PanelPageType>,
        video: Video
    ) -> some View {
        PlayerPanelContentView(
            panelSettings: panelSettings,
            region: region,
            selectedPage: selectedPage,
            context: PanelPageContext(
                appEnvironment: appEnvironment,
                video: video,
                accentColor: accentColor,
                onChannelTap: onChannelTap
            ),
            scrollConfig: PanelScrollConfig(
                topInset: 4,
                bottomInset: 16
            ),
            pageBarTopPadding: 8
        )
        .background(panelBackgroundColor.ignoresSafeArea(edges: .vertical))
    }

    // MARK: - Actions

    private func togglePanel() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPanelVisible.toggle()
            settingsManager?.landscapeDetailsPanelVisible = isPanelVisible
            settingsManager?.detailsPanelLastVisible = isPanelVisible
        }
    }
}

#endif
