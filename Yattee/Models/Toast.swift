//
//  Toast.swift
//  Yattee
//
//  Data models for toast notification system.
//

import Foundation
import SwiftUI

// MARK: - Toast Scope

/// Defines where a toast should be displayed.
enum ToastScope: Hashable, Sendable {
    case main    // Main browsing window (subscriptions, search, etc.)
    case player  // Player window/sheet
}

// MARK: - Toast Category

/// Categories for toast notifications.
/// Same category toasts replace existing ones (no stacking within category).
enum ToastCategory: Hashable, Sendable {
    case loading        // "Loading video..."
    case retry          // "Retrying stream..."
    case remoteControl  // "Receiving remote commands..."
    case sponsorBlock   // "Skipping sponsor"
    case playerStatus   // Generic player status messages
    case download       // Download-related messages
    case error          // Error messages
    case success        // Success messages
    case info           // General info messages

    /// Display priority (higher = shown above others in stack)
    var priority: Int {
        switch self {
        case .error: return 100
        case .sponsorBlock: return 90
        case .retry: return 80
        case .loading: return 70
        case .remoteControl: return 60
        case .playerStatus: return 50
        case .download: return 40
        case .success: return 30
        case .info: return 20
        }
    }
}

// MARK: - Toast Action

/// An action button that can be displayed on a toast.
struct ToastAction: Sendable {
    let label: String
    let systemImage: String?
    let handler: @Sendable @MainActor () async -> Void

    init(
        label: String,
        systemImage: String? = nil,
        handler: @escaping @Sendable @MainActor () async -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.handler = handler
    }
}

extension ToastAction: Equatable {
    static func == (lhs: ToastAction, rhs: ToastAction) -> Bool {
        // Compare by label since handlers can't be compared
        lhs.label == rhs.label && lhs.systemImage == rhs.systemImage
    }
}

// MARK: - Toast

/// A toast notification message.
struct Toast: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The scopes where this toast can be displayed.
    let scopes: Set<ToastScope>
    /// The resolved scope where this toast is actually displayed.
    /// Set by ToastManager when the toast is shown, based on current UI state.
    var activeScope: ToastScope
    let category: ToastCategory
    var title: String
    var subtitle: String?
    var icon: String?
    var iconColor: Color?
    let action: ToastAction?
    let autoDismissDelay: TimeInterval
    /// If true, toast won't auto-dismiss until explicitly dismissed or updated
    let isPersistent: Bool

    init(
        id: UUID = UUID(),
        scopes: Set<ToastScope> = [.main, .player],
        activeScope: ToastScope = .main,
        category: ToastCategory,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        action: ToastAction? = nil,
        autoDismissDelay: TimeInterval = 3.0,
        isPersistent: Bool = false
    ) {
        self.id = id
        self.scopes = scopes
        self.activeScope = activeScope
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.action = action
        self.autoDismissDelay = autoDismissDelay
        self.isPersistent = isPersistent
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.icon == rhs.icon &&
        lhs.iconColor == rhs.iconColor
    }
}
