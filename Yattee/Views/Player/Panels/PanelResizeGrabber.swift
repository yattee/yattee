//
//  PanelResizeGrabber.swift
//  Yattee
//
//  A draggable handle for resizing a details panel's width.
//

import SwiftUI

#if os(iOS) || os(macOS)

/// A draggable handle for resizing the panel width.
struct PanelResizeGrabber: View {
    @Binding var panelWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let panelSide: FloatingPanelSide
    let isPinned: Bool
    @Binding var isDragActive: Bool

    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat? = nil
    @State private var dragStartLocation: CGFloat? = nil
    #if os(macOS)
    @State private var isHovering = false
    #endif

    /// Width of the grabber hit area
    private static let grabberHitWidth: CGFloat = 20

    /// Grabber fill color - needs to be visible against both light (pinned) and dark (floating) backgrounds
    private var grabberColor: Color {
        // When pinned (light background), use a darker gray for visibility
        // When floating (dark background), use lighter color
        let baseColor = isPinned ? Color.gray : Color.secondary
        let isActive = isDragging
        return baseColor.opacity(isActive ? 1.0 : (isPinned ? 0.5 : 0.6))
    }

    var body: some View {
        // Full-height container for expanded hit area
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.grabberHitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                // Visual pill indicator (centered)
                RoundedRectangle(cornerRadius: 3)
                    .fill(grabberColor)
                    .frame(width: 6, height: 40)
            }
            .gesture(dragGesture)
            #if os(macOS)
            .onHover { hovering in
                isHovering = hovering
                isDragActive = hovering || isDragging
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            #endif
            .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                // Capture initial state on first drag event
                if dragStartWidth == nil {
                    dragStartWidth = panelWidth
                    dragStartLocation = value.location.x
                }

                isDragging = true
                isDragActive = true

                guard let startWidth = dragStartWidth,
                      let startLocation = dragStartLocation else { return }

                // Calculate delta from absolute finger position (not translation)
                let locationDelta = value.location.x - startLocation

                // Apply delta based on panel side
                let delta: CGFloat
                if panelSide == .right {
                    delta = -locationDelta
                } else {
                    delta = locationDelta
                }

                let newWidth = startWidth + delta
                panelWidth = min(max(newWidth, minWidth), maxWidth)
            }
            .onEnded { _ in
                dragStartWidth = nil
                dragStartLocation = nil
                isDragging = false
                #if os(macOS)
                isDragActive = isHovering
                #else
                isDragActive = false
                #endif
            }
    }
}

#endif
