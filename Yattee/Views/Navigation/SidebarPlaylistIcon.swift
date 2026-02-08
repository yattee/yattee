//
//  SidebarPlaylistIcon.swift
//  Yattee
//
//  Pre-scaled playlist thumbnail for TabSection labels.
//  TabSection labels don't support frame/resizable modifiers,
//  so we pre-scale the image at the platform image level.
//

import SwiftUI
import Nuke

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A playlist thumbnail that pre-scales the image for use in TabSection labels.
/// Standard SwiftUI frame/resizable modifiers don't work in Tab labels.
struct SidebarPlaylistIcon: View {
    let url: URL?

    // Target size: ~26x15 for 16:9 aspect ratio that fits sidebar row height
    private let targetWidth: CGFloat = 26
    private let targetHeight: CGFloat = 15
    private let cornerRadius: CGFloat = 3

    @State private var platformImage: PlatformImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let platformImage, let scaledImage = scaledImage(from: platformImage) {
                scaledImage
            } else {
                // Fallback - use SF Symbol which scales correctly
                Image(systemName: "list.bullet.rectangle")
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _, _ in
            platformImage = nil
            loadImage()
        }
    }

    @ViewBuilder
    private func scaledImage(from image: PlatformImage) -> Image? {
        #if os(macOS)
        if let scaled = image.scaledRounded(to: NSSize(width: targetWidth, height: targetHeight), cornerRadius: cornerRadius) {
            Image(nsImage: scaled)
        }
        #else
        if let scaled = image.scaledRounded(to: CGSize(width: targetWidth, height: targetHeight), cornerRadius: cornerRadius) {
            Image(uiImage: scaled)
        }
        #endif
    }

    private func loadImage() {
        guard let url, !isLoading else { return }

        // Check memory cache first (synchronous)
        if let cached = ImagePipeline.shared.cache.cachedImage(for: ImageRequest(url: url))?.image {
            platformImage = cached
            return
        }

        isLoading = true

        Task {
            do {
                let image = try await ImagePipeline.shared.image(for: url)
                await MainActor.run {
                    platformImage = image
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Platform Image Scaling

#if os(macOS)
private extension NSImage {
    func scaledRounded(to targetSize: NSSize, cornerRadius: CGFloat) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Create rounded rect clipping path
        let path = NSBezierPath(roundedRect: NSRect(origin: .zero, size: targetSize), xRadius: cornerRadius, yRadius: cornerRadius)
        path.addClip()

        NSGraphicsContext.current?.imageInterpolation = .high

        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }
}
#else
private extension UIImage {
    func scaledRounded(to targetSize: CGSize, cornerRadius: CGFloat) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            // Create rounded rect clipping path
            let rect = CGRect(origin: .zero, size: targetSize)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            path.addClip()

            draw(in: rect)
        }
    }
}
#endif

// MARK: - Preview

#if !os(tvOS)
#Preview {
    List {
        Label {
            Text("My Playlist")
        } icon: {
            SidebarPlaylistIcon(url: nil)
        }

        Label {
            Text("With Thumbnail")
        } icon: {
            SidebarPlaylistIcon(
                url: URL(string: "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")
            )
        }
    }
    .listStyle(.sidebar)
}
#endif
