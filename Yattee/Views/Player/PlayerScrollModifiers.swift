//
//  PlayerScrollModifiers.swift
//  Yattee
//
//  Scroll tracking modifiers for the player sheet.
//

import SwiftUI

#if os(iOS) || os(macOS) || os(tvOS)

// MARK: - Scroll Offset Tracking Modifier

/// Tracks scroll offset using onScrollGeometryChange.
struct ScrollOffsetTrackingModifier: ViewModifier {
    @Binding var scrollOffset: CGFloat
    @Binding var playerHeight: CGFloat
    @Binding var showScrollButton: Bool
    @Binding var isBottomOverscroll: Bool
    var bottomSafeArea: CGFloat
    @State private var isReady = false

    func body(content: Content) -> some View {
        // Only attach scroll geometry tracking after initial layout settles
        if isReady {
            content
                .onScrollGeometryChange(for: ScrollGeometryData.self) { geometry in
                    ScrollGeometryData(
                        contentOffset: geometry.contentOffset.y,
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height
                    )
                } action: { _, newValue in
                    // Only update if values have actually changed
                    if scrollOffset != newValue.contentOffset {
                        scrollOffset = newValue.contentOffset
                    }

                    let shouldShow = newValue.contentOffset > 20
                    if shouldShow != showScrollButton {
                        showScrollButton = shouldShow
                    }

                    let maxOffset = max(0, newValue.contentHeight - newValue.containerHeight)
                    let threshold = bottomSafeArea * 2 + 50
                    let newIsBottomOverscroll = newValue.contentOffset > maxOffset - threshold
                    if newIsBottomOverscroll != isBottomOverscroll {
                        isBottomOverscroll = newIsBottomOverscroll
                    }
                }
        } else {
            content
                .onAppear {
                    // Delay attaching scroll tracking to avoid initial layout updates
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        isReady = true
                    }
                }
        }
    }
}

/// Data structure for scroll geometry tracking
struct ScrollGeometryData: Equatable {
    let contentOffset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
}

#endif
