//
//  BlurredImageBackground.swift
//  Yattee
//
//  Reusable blurred image background component for ambient visual effects.
//

import SwiftUI
import NukeUI

/// A blurred, oversized image background that creates an ambient glow effect.
/// Commonly used behind album art or video thumbnails for a visually appealing background.
struct BlurredImageBackground: View {
    let url: URL?
    var videoID: String?  // Explicit video identifier for comparison
    var blurRadius: CGFloat = 60
    var scale: CGFloat = 1.8
    var gradientColor: Color = .clear
    var transitionDuration: Double = 0.4
    var contentOpacity: Double = 1.0  // Opacity for blurred content (not gradient)

    @State private var displayedImage: Image?
    @State private var previousImage: Image?
    @State private var transitionOpacity: Double = 1.0
    @State private var loadedVideoID: String?
    @State private var animatedContentOpacity: Double = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Blur content layer - masked to fade at bottom
                ZStack(alignment: .top) {
                    // Previous image layer (fades out during transition)
                    if let previous = previousImage {
                        previous
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: blurRadius)
                            .scaleEffect(scale)
                            .opacity((1.0 - transitionOpacity) * animatedContentOpacity)
                    }

                    // Current image layer (fades in during transition)
                    if let current = displayedImage {
                        current
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .blur(radius: blurRadius)
                            .scaleEffect(scale)
                            .opacity(transitionOpacity * animatedContentOpacity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.9), location: 0.1),
                            .init(color: .black.opacity(0.8), location: 0.2),
                            .init(color: .black.opacity(0.7), location: 0.3),
                            .init(color: .black.opacity(0.6), location: 0.4),
                            .init(color: .black.opacity(0.5), location: 0.5),
                            .init(color: .black.opacity(0.4), location: 0.6),
                            .init(color: .black.opacity(0.25), location: 0.7),
                            .init(color: .black.opacity(0.1), location: 0.85),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

                // Hidden LazyImage for loading
                LazyImage(url: url) { state in
                    Color.clear
                        .onChange(of: state.image) { _, newImage in
                            if let newImage {
                                handleNewImage(newImage)
                            }
                        }
                        .onAppear {
                            if let image = state.image {
                                handleNewImage(image)
                            }
                        }
                }
                .frame(width: 1, height: 1)
                .opacity(0)

                // Gradient overlay - fills full geometry
                if gradientColor != .clear {
                    LinearGradient(
                        stops: [
                            .init(color: gradientColor.opacity(0.1), location: 0),
                            .init(color: gradientColor.opacity(0.15), location: 0.1),
                            .init(color: gradientColor.opacity(0.2), location: 0.2),
                            .init(color: gradientColor.opacity(0.3), location: 0.3),
                            .init(color: gradientColor.opacity(0.4), location: 0.4),
                            .init(color: gradientColor.opacity(0.5), location: 0.5),
                            .init(color: gradientColor.opacity(0.6), location: 0.6),
                            .init(color: gradientColor.opacity(0.75), location: 0.7),
                            .init(color: gradientColor.opacity(0.9), location: 0.85),
                            .init(color: gradientColor.opacity(1.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            animatedContentOpacity = contentOpacity
        }
        .onChange(of: contentOpacity) { _, newValue in
            withAnimation(.easeInOut(duration: transitionDuration)) {
                animatedContentOpacity = newValue
            }
        }
    }

    private func handleNewImage(_ newImage: Image) {
        // First image load - no animation needed
        guard displayedImage != nil else {
            displayedImage = newImage
            loadedVideoID = videoID
            return
        }

        // Skip animation if this is the same video (e.g., thumbnail quality upgrade)
        if let loadedVideoID, let videoID, loadedVideoID == videoID {
            displayedImage = newImage
            self.loadedVideoID = videoID
            return
        }

        // Different video - animate crossfade
        // Use transaction to ensure all initial state changes happen together without animation
        // This prevents the flash where new image appears at full opacity before transitionOpacity is set to 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            previousImage = displayedImage
            displayedImage = newImage
            loadedVideoID = videoID
            transitionOpacity = 0
        }

        // Animate the crossfade
        withAnimation(.easeInOut(duration: transitionDuration)) {
            transitionOpacity = 1.0
        }

        // Clean up previous image after transition
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(transitionDuration + 0.1))
            previousImage = nil
        }
    }
}

// MARK: - Platform-Specific Defaults

extension BlurredImageBackground {
    /// Platform-specific blur radius defaults
    static var platformBlurRadius: CGFloat {
        #if os(tvOS)
        return 40
        #elseif os(macOS)
        return 50
        #else
        return 60
        #endif
    }
}

#Preview {
    ZStack {
        BlurredImageBackground(
            url: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"),
            videoID: "dQw4w9WgXcQ",
            blurRadius: 60,
            scale: 1.8,
            gradientColor: Color(.black)
        )
        .frame(height: 400)

        VStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.gray)
                .frame(width: 280, height: 158)

            Text(verbatim: "Video Title")
                .font(.headline)
        }
    }
}
