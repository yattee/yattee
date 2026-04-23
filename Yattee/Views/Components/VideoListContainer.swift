//
//  VideoListContainer.swift
//  Yattee
//
//  Reusable container for video list layouts with inset/plain styling.
//

import SwiftUI

/// A container that handles inset/plain list styling with proper backgrounds and card layout.
///
/// This component eliminates the need for duplicate inset/plain implementations
/// across video list views by encapsulating the platform-specific background
/// handling and card styling.
///
/// Usage:
/// ```swift
/// VideoListContainer(listStyle: listStyle, rowStyle: rowStyle) {
///     // Optional header content (banners, section headers)
///     feedStatusBanner
/// } content: {
///     ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
///         VideoListRow(
///             isLast: index == videos.count - 1,
///             rowStyle: rowStyle,
///             listStyle: listStyle
///         ) {
///             VideoRowView(video: video, style: rowStyle)
///                 .tappableVideo(video)
///         }
///     }
/// }
/// ```
struct VideoListContainer<Header: View, Content: View, Footer: View>: View {
    let listStyle: VideoListStyle
    let rowStyle: VideoRowStyle

    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    /// Corner radius for card container in inset style.
    private let cardCornerRadius: CGFloat = 10

    /// Horizontal padding for card container.
    private let cardHorizontalPadding: CGFloat = 16

    /// Bottom padding for card container.
    private let cardBottomPadding: CGFloat = 16

    var body: some View {
        #if os(tvOS)
        // tvOS: Simple ScrollView without background overlay
        ScrollView {
            LazyVStack(spacing: 0) {
                header()
                content()
                footer()
            }
        }
        .scrollClipDisabled()
        #else
        // iOS/macOS: Background overlay pattern
        backgroundStyle.color
            .ignoresSafeArea()
            .overlay(
                ScrollView {
                    LazyVStack(spacing: 0) {
                        header()

                        if listStyle == .inset {
                            insetCardContent
                        } else {
                            plainContent
                        }

                        footer()
                    }
                }
            )
        #endif
    }

    // MARK: - Private

    private var backgroundStyle: ListBackgroundStyle {
        listStyle == .inset ? .grouped : .plain
    }

    private var insetCardContent: some View {
        LazyVStack(spacing: 0) {
            content()
        }
        .background(ListBackgroundStyle.card.color)
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius))
        .padding(.horizontal, cardHorizontalPadding)
        .padding(.bottom, cardBottomPadding)
    }

    private var plainContent: some View {
        LazyVStack(spacing: 0) {
            content()
        }
        .padding(.bottom, cardBottomPadding)
    }
}

// MARK: - Convenience Initializers

extension VideoListContainer where Header == EmptyView, Footer == EmptyView {
    /// Creates a video list container without a header or footer.
    init(
        listStyle: VideoListStyle,
        rowStyle: VideoRowStyle,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.listStyle = listStyle
        self.rowStyle = rowStyle
        self.header = { EmptyView() }
        self.content = content
        self.footer = { EmptyView() }
    }
}

extension VideoListContainer where Footer == EmptyView {
    /// Creates a video list container with a header but no footer.
    init(
        listStyle: VideoListStyle,
        rowStyle: VideoRowStyle,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.listStyle = listStyle
        self.rowStyle = rowStyle
        self.header = header
        self.content = content
        self.footer = { EmptyView() }
    }
}

extension VideoListContainer where Header == EmptyView {
    /// Creates a video list container with a footer but no header.
    init(
        listStyle: VideoListStyle,
        rowStyle: VideoRowStyle,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.listStyle = listStyle
        self.rowStyle = rowStyle
        self.header = { EmptyView() }
        self.content = content
        self.footer = footer
    }
}

// MARK: - Preview

#Preview("Inset Style") {
    VideoListContainer(listStyle: .inset, rowStyle: .regular) {
        Text("Header")
            .padding()
    } content: {
        ForEach(0..<5) { index in
            VideoListRow(
                isLast: index == 4,
                rowStyle: .regular,
                listStyle: .inset
            ) {
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 68)
                    VStack(alignment: .leading) {
                        Text(verbatim: "Video Title \(index + 1)")
                            .font(.subheadline)
                        Text(verbatim: "Channel Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}

#Preview("Plain Style") {
    VideoListContainer(listStyle: .plain, rowStyle: .regular) {
        ForEach(0..<5) { index in
            VideoListRow(
                isLast: index == 4,
                rowStyle: .regular,
                listStyle: .plain
            ) {
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 68)
                    VStack(alignment: .leading) {
                        Text(verbatim: "Video Title \(index + 1)")
                            .font(.subheadline)
                        Text(verbatim: "Channel Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}
