//
//  TapZoneCalculator.swift
//  Yattee
//
//  Calculator for determining tap zone hit-testing and frames.
//

#if os(iOS)
import CoreGraphics
import Foundation

/// Utility for calculating tap zone positions and hit-testing.
enum TapZoneCalculator {
    /// Safe margin from screen edges to avoid system gesture conflicts.
    static let safeMargin: CGFloat = 25

    /// Determines which zone was tapped based on the layout and tap point.
    /// - Parameters:
    ///   - point: The tap location in the bounds coordinate system.
    ///   - bounds: The total gesture-recognizable area bounds.
    ///   - layout: The current tap zone layout.
    /// - Returns: The zone position that was tapped, or nil if outside safe margins.
    static func zone(
        for point: CGPoint,
        in bounds: CGRect,
        layout: TapZoneLayout
    ) -> TapZonePosition? {
        // Check safe margins
        let safeArea = bounds.insetBy(dx: safeMargin, dy: safeMargin)
        guard safeArea.contains(point) else { return nil }

        // Normalize point to 0-1 range within safe area
        let normalizedX = (point.x - safeArea.minX) / safeArea.width
        let normalizedY = (point.y - safeArea.minY) / safeArea.height

        switch layout {
        case .single:
            return .full

        case .horizontalSplit:
            return normalizedX < 0.5 ? .left : .right

        case .verticalSplit:
            return normalizedY < 0.5 ? .top : .bottom

        case .threeColumns:
            if normalizedX < 1.0 / 3.0 {
                return .leftThird
            } else if normalizedX < 2.0 / 3.0 {
                return .center
            } else {
                return .rightThird
            }

        case .quadrants:
            let isTop = normalizedY < 0.5
            let isLeft = normalizedX < 0.5

            if isTop {
                return isLeft ? .topLeft : .topRight
            } else {
                return isLeft ? .bottomLeft : .bottomRight
            }
        }
    }
}
#endif
