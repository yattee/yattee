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
    @Environment(\.appEnvironment) private var appEnvironment

    @Binding var panelWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let panelSide: FloatingPanelSide
    let isPinned: Bool
    @Binding var isDragActive: Bool

    /// Width of the grabber hit area (hosts can narrow it, e.g. corner layout)
    var hitWidth: CGFloat = PanelResizeGrabber.grabberHitWidth

    /// Whether the strip frame is published to the dismiss-pan exclusion
    /// (hosts pass false while the grabber is in the hierarchy but covered).
    var publishesFrame: Bool = true

    /// Overdrag past `minWidth`: reports how far (in points, ≥ 0) the finger
    /// went beyond the minimum while the width stays clamped — hosts can
    /// slide the panel off-screen with it. Reported every drag update, so a
    /// finger coming back above the minimum reports 0 again.
    var onOverdragChanged: ((CGFloat) -> Void)? = nil
    /// Release after an overdrag: final overshoot and the predicted overshoot
    /// (from the drag's projected end location) for flick detection.
    var onOverdragEnded: ((_ overshoot: CGFloat, _ predictedOvershoot: CGFloat) -> Void)? = nil

    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat? = nil
    @State private var dragStartLocation: CGFloat? = nil
    #if os(macOS)
    @State private var isHovering = false
    #endif

    /// Width of the grabber hit area
    static let grabberHitWidth: CGFloat = 20

    /// Grabber fill color - needs to be visible against both light (pinned) and dark (floating) backgrounds
    private var grabberColor: Color {
        // Pinned matches the panel drag handle (secondary 0.4);
        // floating (dark background) stays a bit lighter
        let isActive = isDragging
        return Color.secondary.opacity(isActive ? 1.0 : (isPinned ? 0.4 : 0.6))
    }

    var body: some View {
        // Full-height container for expanded hit area
        Rectangle()
            .fill(Color.clear)
            .frame(width: hitWidth)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay {
                // Visual pill indicator (centered) — sized like the panel
                // drag handle capsule (36x4), rotated vertical
                Capsule()
                    .fill(grabberColor)
                    .frame(width: 4, height: 36)
            }
            .gesture(dragGesture)
            #if os(iOS)
            // Publish the strip frame (with slop) so the window-level dismiss
            // pan never begins from a resize drag — a diagonal start would
            // otherwise cancel the resize and dismiss the player instead
            .background {
                GeometryReader { proxy in
                    let frame = publishesFrame ? proxy.frame(in: .global).insetBy(dx: -8, dy: 0) : .zero
                    Color.clear
                        .onChange(of: frame, initial: true) { _, frame in
                            appEnvironment?.navigationCoordinator.panelResizeGrabberFrame = frame
                        }
                        .onDisappear {
                            appEnvironment?.navigationCoordinator.panelResizeGrabberFrame = .zero
                        }
                }
            }
            #endif
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
                onOverdragChanged?(max(0, minWidth - newWidth))
            }
            .onEnded { value in
                if let onOverdragEnded,
                   let startWidth = dragStartWidth,
                   let startLocation = dragStartLocation {
                    let overshoot = { (locationX: CGFloat) -> CGFloat in
                        let locationDelta = locationX - startLocation
                        let delta = panelSide == .right ? -locationDelta : locationDelta
                        return max(0, minWidth - (startWidth + delta))
                    }
                    onOverdragEnded(overshoot(value.location.x), overshoot(value.predictedEndLocation.x))
                }
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
