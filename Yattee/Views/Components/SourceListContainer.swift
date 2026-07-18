//
//  SourceListContainer.swift
//  Yattee
//
//  Container for source list views with inset/plain styling.
//

import SwiftUI

/// A container that handles inset/plain list styling for source views.
///
/// Simplified version of VideoListContainer for simpler source rows.
struct SourceListContainer<Header: View, Content: View>: View {
    let listStyle: VideoListStyle

    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content

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
            }
        }
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

extension SourceListContainer where Header == EmptyView {
    /// Creates a source list container without a header.
    init(
        listStyle: VideoListStyle,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.listStyle = listStyle
        self.header = { EmptyView() }
        self.content = content
    }
}

// MARK: - Preview

#Preview("Inset Style") {
    SourceListContainer(listStyle: .inset) {
        Text("Header")
            .padding()
    } content: {
        ForEach(0..<5) { index in
            SourceListRow(isLast: index == 4, listStyle: .inset) {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading) {
                        Text("Source \(index + 1)")
                            .font(.headline)
                        Text("example.com")
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
    SourceListContainer(listStyle: .plain) {
        ForEach(0..<5) { index in
            SourceListRow(isLast: index == 4, listStyle: .plain) {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading) {
                        Text("Source \(index + 1)")
                            .font(.headline)
                        Text("example.com")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
    }
}
