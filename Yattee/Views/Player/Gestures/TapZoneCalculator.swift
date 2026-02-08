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

    /// Returns the frame for a specific zone position within bounds.
    /// - Parameters:
    ///   - position: The zone position.
    ///   - bounds: The total gesture-recognizable area bounds.
    ///   - layout: The current tap zone layout.
    /// - Returns: The frame for the zone, or nil if position doesn't match layout.
    static func frame(
        for position: TapZonePosition,
        in bounds: CGRect,
        layout: TapZoneLayout
    ) -> CGRect? {
        // Use safe area for calculations
        let safeArea = bounds.insetBy(dx: safeMargin, dy: safeMargin)

        switch layout {
        case .single:
            guard position == .full else { return nil }
            return safeArea

        case .horizontalSplit:
            let halfWidth = safeArea.width / 2
            switch position {
            case .left:
                return CGRect(x: safeArea.minX, y: safeArea.minY,
                              width: halfWidth, height: safeArea.height)
            case .right:
                return CGRect(x: safeArea.minX + halfWidth, y: safeArea.minY,
                              width: halfWidth, height: safeArea.height)
            default:
                return nil
            }

        case .verticalSplit:
            let halfHeight = safeArea.height / 2
            switch position {
            case .top:
                return CGRect(x: safeArea.minX, y: safeArea.minY,
                              width: safeArea.width, height: halfHeight)
            case .bottom:
                return CGRect(x: safeArea.minX, y: safeArea.minY + halfHeight,
                              width: safeArea.width, height: halfHeight)
            default:
                return nil
            }

        case .threeColumns:
            let thirdWidth = safeArea.width / 3
            switch position {
            case .leftThird:
                return CGRect(x: safeArea.minX, y: safeArea.minY,
                              width: thirdWidth, height: safeArea.height)
            case .center:
                return CGRect(x: safeArea.minX + thirdWidth, y: safeArea.minY,
                              width: thirdWidth, height: safeArea.height)
            case .rightThird:
                return CGRect(x: safeArea.minX + thirdWidth * 2, y: safeArea.minY,
                              width: thirdWidth, height: safeArea.height)
            default:
                return nil
            }

        case .quadrants:
            let halfWidth = safeArea.width / 2
            let halfHeight = safeArea.height / 2
            switch position {
            case .topLeft:
                return CGRect(x: safeArea.minX, y: safeArea.minY,
                              width: halfWidth, height: halfHeight)
            case .topRight:
                return CGRect(x: safeArea.minX + halfWidth, y: safeArea.minY,
                              width: halfWidth, height: halfHeight)
            case .bottomLeft:
                return CGRect(x: safeArea.minX, y: safeArea.minY + halfHeight,
                              width: halfWidth, height: halfHeight)
            case .bottomRight:
                return CGRect(x: safeArea.minX + halfWidth, y: safeArea.minY + halfHeight,
                              width: halfWidth, height: halfHeight)
            default:
                return nil
            }
        }
    }
}
#endif
