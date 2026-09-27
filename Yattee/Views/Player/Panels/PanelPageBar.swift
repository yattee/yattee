//
//  PanelPageBar.swift
//  Yattee
//
//  Scrolling pill row for switching details panel pages.
//

import SwiftUI

#if os(iOS) || os(macOS)

/// Pin control shown at the leading edge of the page bar.
struct PanelPageBarPinAction {
    let isPinned: Bool
    let toggle: () -> Void
}

struct PanelPageBar: View {
    let pages: [PanelPageConfiguration]
    @Binding var selectedPage: PanelPageType
    let accentColor: Color
    var showLabels: Bool = true
    /// Optional pin control rendered as an icon-only pill before the pages
    /// (wide layout: pinned side-by-side vs. floating).
    var pinAction: PanelPageBarPinAction? = nil

    @Environment(\.panelHorizontalInsets) private var insets
    @Environment(\.appEnvironment) private var appEnvironment

    /// Pills sit 4pt closer to the edge than page content (12 vs 16 with the
    /// standard inset); a host that trims the content inset (corner side
    /// column) trims the bar the same way so the first pill lines up.
    private static let pillEdgeOffset: CGFloat = 4

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 8) {
                if let pinAction {
                    pinButton(pinAction)
                        .padding(.leading, max(0, insets.leading - Self.pillEdgeOffset))
                        .padding(.vertical, 6)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pages) { page in
                            pageButton(page.pageType)
                                .id(page.pageType)
                        }
                    }
                    .padding(.leading, pinAction == nil ? max(0, insets.leading - Self.pillEdgeOffset) : 0)
                    .padding(.trailing, max(0, insets.trailing - Self.pillEdgeOffset))
                    .padding(.vertical, 6)
                }
            }
            .onChange(of: selectedPage) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// Icon-only pill toggling the pinned state; filled with the accent
    /// color while pinned so it reads like a selected page.
    @ViewBuilder
    private func pinButton(_ pin: PanelPageBarPinAction) -> some View {
        Button {
            #if os(iOS)
            appEnvironment?.settingsManager.triggerHapticFeedback(for: .subscribeButton)
            #endif
            pin.toggle()
        } label: {
            Image(systemName: pin.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(pin.isPinned ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(pin.isPinned ? AnyShapeStyle(accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(pin.isPinned
            ? String(localized: "wideLayoutPanel.pinButton.unpin")
            : String(localized: "wideLayoutPanel.pinButton.pin"))
    }

    @ViewBuilder
    private func pageButton(_ pageType: PanelPageType) -> some View {
        let isSelected = pageType == selectedPage

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPage = pageType
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: pageType.systemImage)
                    .font(.system(size: 13, weight: .medium))

                if showLabels || isSelected {
                    Text(pageType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)))
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#endif
