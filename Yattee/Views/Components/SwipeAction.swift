//
//  SwipeAction.swift
//  Yattee
//
//  Custom swipe actions for list views (similar to Mail swipe actions).
//

import SwiftUI

/// Model representing a single swipe action button.
struct SwipeAction: Identifiable {
    var id = UUID().uuidString
    var symbolImage: String
    var tint: Color
    var background: Color
    var font: Font = .title3
    var size: CGSize = CGSize(width: 45, height: 45)
    var action: (_ reset: @escaping () -> Void) -> Void
}

/// Result builder for declarative swipe action definitions.
@resultBuilder
struct SwipeActionBuilder {
    static func buildBlock(_ components: SwipeAction...) -> [SwipeAction] {
        components
    }
}

/// Configuration for swipe action layout and behavior.
struct SwipeActionConfig {
    var leadingPadding: CGFloat = 0
    var trailingPadding: CGFloat = 10
    var spacing: CGFloat = 10
    var occupiesFullWidth: Bool = false
}
