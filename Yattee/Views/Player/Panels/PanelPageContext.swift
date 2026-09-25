//
//  PanelPageContext.swift
//  Yattee
//
//  Shared context and scroll plumbing for the details panel pages.
//

import SwiftUI

#if os(iOS) || os(macOS)

// MARK: - Page Context

/// Lightweight context handed to every panel page. Pages reach services via
/// `appEnvironment`; only host-specific callbacks travel explicitly.
struct PanelPageContext {
    let appEnvironment: AppEnvironment?
    let video: Video
    let accentColor: Color
    var onChannelTap: (() -> Void)?
}

// MARK: - Scroll Config

/// Scroll behavior the host wants applied to scrollable pages: content
/// insets, scroll-offset reporting (pills collapse / scroll-to-top button),
/// and the portrait overscroll-to-collapse gesture.
struct PanelScrollConfig {
    /// Extra space above the content (e.g. below the drag handle).
    var topInset: CGFloat = 10

    /// Extra space below the content so it can scroll above pills/fades.
    var bottomInset: CGFloat = 80

    /// Reports the current scroll offset (0 at top, positive when scrolled).
    var scrollOffsetChanged: ((CGFloat) -> Void)?

    /// Toggling this scrolls the page back to the top.
    var scrollToTopTrigger: Bool = false

    /// Identity of the content being shown (the video). When it changes the
    /// page jumps back to the top without animation so the new title is
    /// visible. Set by `PlayerPanelContentView`.
    var contentID: AnyHashable?

    /// Disables scrolling (while the portrait drag handle is active).
    var isScrollDisabled: Bool = false

    /// Portrait overscroll-to-collapse drag callbacks (iOS only).
    var onOverscrollDragChanged: ((CGFloat) -> Void)?
    var onOverscrollDragEnded: ((CGFloat, CGFloat) -> Void)?
}

// MARK: - Horizontal Insets

/// Horizontal content insets a host wants on the panel pages. Hosts whose
/// panel already carries leading chrome (the corner side column's resize
/// grabber strip) narrow the leading inset so content sits the same distance
/// from both edges.
struct PanelHorizontalInsets: Equatable {
    static let standard: CGFloat = 16

    var leading: CGFloat = PanelHorizontalInsets.standard
    var trailing: CGFloat = PanelHorizontalInsets.standard

    /// Leading delta relative to the standard inset; List-backed pages
    /// (queue, tracks) apply it as a scroll content margin since their
    /// section insets can't be restyled per host.
    var leadingListAdjustment: CGFloat { leading - Self.standard }
}

private struct PanelHorizontalInsetsKey: EnvironmentKey {
    static let defaultValue = PanelHorizontalInsets()
}

extension EnvironmentValues {
    var panelHorizontalInsets: PanelHorizontalInsets {
        get { self[PanelHorizontalInsetsKey.self] }
        set { self[PanelHorizontalInsetsKey.self] = newValue }
    }
}

private struct PanelHorizontalPadding: ViewModifier {
    @Environment(\.panelHorizontalInsets) private var insets

    func body(content: Content) -> some View {
        content
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
    }
}

private struct PanelListLeadingMargin: ViewModifier {
    @Environment(\.panelHorizontalInsets) private var insets

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, insets.leadingListAdjustment, for: .scrollContent)
    }
}

extension View {
    /// Host-configurable replacement for `.padding(.horizontal)` on panel
    /// page content.
    func panelHorizontalPadding() -> some View {
        modifier(PanelHorizontalPadding())
    }

    /// Shifts List-backed page content by the host's leading inset delta.
    func panelListLeadingMargin() -> some View {
        modifier(PanelListLeadingMargin())
    }
}

// MARK: - Page Scroll View

/// Shared scroll container used by the scrollable panel pages. Applies the
/// host's insets, reports scroll offset, handles scroll-to-top, and attaches
/// the portrait overscroll gesture when the host provides callbacks.
struct PanelPageScrollView<Content: View>: View {
    let config: PanelScrollConfig
    @ViewBuilder let content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id("panelPageTop")
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .named("panelPageScroll")).origin.y) { _, newValue in
                                        config.scrollOffsetChanged?(max(0, -newValue))
                                    }
                            }
                        )

                    Color.clear
                        .frame(height: config.topInset)

                    content

                    Spacer()
                        .frame(height: config.bottomInset)
                }
            }
            .coordinateSpace(name: "panelPageScroll")
            #if os(iOS)
            .background {
                if config.onOverscrollDragChanged != nil || config.onOverscrollDragEnded != nil {
                    OverscrollGestureView(
                        isEnabled: !config.isScrollDisabled,
                        onDragChanged: { offset in
                            config.onOverscrollDragChanged?(offset)
                        },
                        onDragEnded: { offset, predicted in
                            config.onOverscrollDragEnded?(offset, predicted)
                        }
                    )
                }
            }
            #endif
            .scrollDisabled(config.isScrollDisabled)
            .onChange(of: config.scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("panelPageTop", anchor: .top)
                }
            }
            .onChange(of: config.contentID) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("panelPageTop", anchor: .top)
                }
                config.scrollOffsetChanged?(0)
            }
        }
    }
}

#endif
