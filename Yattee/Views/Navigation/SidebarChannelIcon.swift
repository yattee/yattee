//
//  SidebarChannelIcon.swift
//  Yattee
//
//  Pre-scaled channel icon for TabSection labels.
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

/// A channel icon that pre-scales the image for use in TabSection labels.
/// Standard SwiftUI frame/resizable modifiers don't work in Tab labels.
struct SidebarChannelIcon: View {
    let url: URL?
    let name: String
    var authHeader: String?

    private let size: CGFloat = 22

    @State private var platformImage: PlatformImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let platformImage, let scaledImage = scaledImage(from: platformImage) {
                scaledImage
            } else {
                // Placeholder - use SF Symbol which scales correctly
                Image(systemName: "person.circle.fill")
                    .symbolRenderingMode(.hierarchical)
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
        if let scaled = image.scaledCircular(to: NSSize(width: size, height: size)) {
            Image(nsImage: scaled)
        }
        #else
        if let scaled = image.scaledCircular(to: CGSize(width: size, height: size)) {
            Image(uiImage: scaled)
        }
        #endif
    }

    private func loadImage() {
        guard let request = AvatarURLBuilder.imageRequest(url: url, authHeader: authHeader), !isLoading else { return }

        // Check memory cache first (synchronous)
        if let cached = ImagePipeline.shared.cache.cachedImage(for: request)?.image {
            platformImage = cached
            return
        }

        isLoading = true

        Task {
            do {
                let image = try await ImagePipeline.shared.image(for: request)
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
    func scaledCircular(to targetSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()

        // Create circular clipping path
        let path = NSBezierPath(ovalIn: NSRect(origin: .zero, size: targetSize))
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
    func scaledCircular(to targetSize: CGSize) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            // Create circular clipping path
            let rect = CGRect(origin: .zero, size: targetSize)
            context.cgContext.addEllipse(in: rect)
            context.cgContext.clip()

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
            Text("Apple")
        } icon: {
            SidebarChannelIcon(url: nil, name: "Apple")
        }

        Label {
            Text("Test Channel")
        } icon: {
            SidebarChannelIcon(
                url: URL(string: "https://example.com/avatar.jpg"),
                name: "Test"
            )
        }
    }
    .listStyle(.sidebar)
}
#endif
