//
//  LoadMoreTrigger.swift
//  Yattee
//
//  Reusable infinite scroll trigger component.
//

import SwiftUI

/// A reusable component for triggering infinite scroll loading.
///
/// Place this at the end of a list to automatically trigger loading more content
/// when scrolled into view. Shows a loading indicator while content is being fetched.
///
/// Usage:
/// ```swift
/// LazyVStack {
///     ForEach(videos) { video in
///         VideoRowView(video: video)
///     }
///     
///     LoadMoreTrigger(
///         isLoading: isLoadingMore,
///         hasMore: continuation != nil
///     ) {
///         Task { await loadMore() }
///     }
/// }
/// ```
struct LoadMoreTrigger: View {
    /// Whether content is currently being loaded.
    let isLoading: Bool

    /// Whether there is more content available to load.
    let hasMore: Bool

    /// Action to perform when more content should be loaded.
    let onLoadMore: () -> Void

    var body: some View {
        Group {
            if hasMore && !isLoading {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        onLoadMore()
                    }
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        LazyVStack {
            ForEach(0..<10) { index in
                Text("Item \(index)")
                    .padding()
            }

            LoadMoreTrigger(
                isLoading: true,
                hasMore: true
            ) {}
        }
    }
}
