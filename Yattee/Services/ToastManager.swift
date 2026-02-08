//
//  ToastManager.swift
//  Yattee
//
//  Manages toast notification lifecycle and display queue.
//

import Foundation
import SwiftUI

/// Manages toast notifications across the app.
@MainActor
@Observable
final class ToastManager {
    // MARK: - State

    /// Active toasts, sorted by priority (highest first)
    private(set) var activeToasts: [Toast] = []

    /// Auto-dismiss tasks keyed by toast ID
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    /// Reference to navigation coordinator for checking player visibility.
    private weak var navigationCoordinator: NavigationCoordinator?

    /// Task for observing player visibility changes.
    private var playerVisibilityObserverTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Set the navigation coordinator reference.
    func setNavigationCoordinator(_ coordinator: NavigationCoordinator) {
        self.navigationCoordinator = coordinator
        startPlayerVisibilityObserver()
    }

    // MARK: - Scope Resolution

    /// Determines whether the player is currently visible (expanded sheet on iOS, window on macOS).
    private var isPlayerVisible: Bool {
        #if os(macOS)
        return ExpandedPlayerWindowManager.shared.isPresented
        #else
        return navigationCoordinator?.isPlayerExpanded ?? false
        #endif
    }

    /// Resolves the active scope for a toast based on current UI state.
    /// If player is visible and the toast supports player scope, use player.
    /// Otherwise use main scope if supported.
    private func resolveActiveScope(for scopes: Set<ToastScope>) -> ToastScope {
        if isPlayerVisible && scopes.contains(.player) {
            return .player
        }
        if scopes.contains(.main) {
            return .main
        }
        // Fallback to first available scope
        return scopes.first ?? .main
    }

    /// Re-evaluates and updates the active scope for all toasts based on current player visibility.
    /// This allows toasts to migrate from .main to .player when the player becomes visible.
    private func updateToastScopes() {
        guard !self.activeToasts.isEmpty else { return }
        
        LoggingService.shared.info("🔄 Updating toast scopes - \(self.activeToasts.count) active toast(s), player visible: \(self.isPlayerVisible)", category: .general)
        
        var updated = false
        for index in self.activeToasts.indices {
            let toast = self.activeToasts[index]
            let newActiveScope = resolveActiveScope(for: toast.scopes)
            if toast.activeScope != newActiveScope {
                LoggingService.shared.info("📱 Migrating toast '\(toast.title)' from \(String(describing: toast.activeScope)) to \(String(describing: newActiveScope))", category: .general)
                self.activeToasts[index].activeScope = newActiveScope
                updated = true
            }
        }
        
        // Trigger UI update if any scopes changed
        if updated {
            LoggingService.shared.info("✅ Toast scope migration complete - UI will refresh", category: .general)
            // The @Observable macro will handle change notifications automatically
            // Just need to ensure the array mutation is detected
            self.activeToasts = self.activeToasts
        }
    }

    /// Start observing player visibility changes to migrate toasts between scopes.
    private func startPlayerVisibilityObserver() {
        playerVisibilityObserverTask?.cancel()
        
        playerVisibilityObserverTask = Task { [weak self] in
            guard let self else { return }
            
            var lastPlayerVisible = self.isPlayerVisible
            
            while !Task.isCancelled {
                // Wait for navigationCoordinator.isPlayerExpanded to change
                // (On macOS, ExpandedPlayerWindowManager.isPresented is updated when window shows,
                // but we track the NavigationCoordinator state which triggers the window)
                if let coordinator = self.navigationCoordinator {
                    _ = withObservationTracking {
                        coordinator.isPlayerExpanded
                    } onChange: { }
                }
                
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { break }
                
                let currentPlayerVisible = self.isPlayerVisible
                if currentPlayerVisible != lastPlayerVisible {
                    LoggingService.shared.info("Player visibility changed: \(lastPlayerVisible) -> \(currentPlayerVisible)", category: .general)
                    lastPlayerVisible = currentPlayerVisible
                    self.updateToastScopes()
                }
            }
        }
    }

    // MARK: - Filtered Access

    /// Returns toasts for a specific scope (filtered by activeScope).
    func toasts(for scope: ToastScope) -> [Toast] {
        activeToasts.filter { $0.activeScope == scope }
    }

    // MARK: - Public API

    /// Show a toast notification.
    /// The toast will be displayed in the most appropriate scope based on current UI state.
    /// If a toast with the same category exists in any scope, it will be replaced.
    /// - Parameters:
    ///   - scopes: The scopes where this toast can be displayed (default: main and player)
    ///   - category: The category of the toast (affects replacement and priority)
    ///   - title: The title to display
    ///   - subtitle: Optional subtitle for additional context
    ///   - icon: Optional SF Symbol name
    ///   - iconColor: Optional icon color
    ///   - action: Optional action button
    ///   - autoDismissDelay: Time before auto-dismiss (default: 3s)
    ///   - isPersistent: If true, won't auto-dismiss
    /// - Returns: The ID of the shown toast
    @discardableResult
    func show(
        scopes: Set<ToastScope> = [.main, .player],
        category: ToastCategory,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        action: ToastAction? = nil,
        autoDismissDelay: TimeInterval = 3.0,
        isPersistent: Bool = false
    ) -> UUID {
        // Resolve the active scope based on current UI state
        let activeScope = resolveActiveScope(for: scopes)

        let toast = Toast(
            scopes: scopes,
            activeScope: activeScope,
            category: category,
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconColor: iconColor,
            action: action,
            autoDismissDelay: autoDismissDelay,
            isPersistent: isPersistent
        )

        // Cancel and remove existing toast with same category (in any scope)
        if let existingToast = activeToasts.first(where: { $0.category == category }) {
            LoggingService.shared.info("Replacing toast for category: \(String(describing: category))", category: .general)
            dismissInternal(id: existingToast.id, animated: false)
        }

        // Add new toast and sort by priority
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            activeToasts.append(toast)
            activeToasts.sort { $0.category.priority > $1.category.priority }
        }

        let scopesStr = scopes.map { String(describing: $0) }.joined(separator: ", ")
        let playerVisible = self.isPlayerVisible
        LoggingService.shared.info("📢 Showing toast: '\(title)' in scope: \(String(describing: activeScope)) (supports: [\(scopesStr)]), persistent: \(isPersistent), player visible: \(playerVisible)", category: .general)

        // Schedule auto-dismiss
        // For persistent toasts, autoDismissDelay acts as a safety timeout to prevent stuck toasts
        if !isPersistent || autoDismissDelay > 0 {
            scheduleAutoDismiss(for: toast)
        }

        return toast.id
    }

    /// Update an existing toast's title/subtitle and icon, then schedule auto-dismiss.
    /// Used for persistent toasts that need to show a final state before dismissing.
    func update(
        id: UUID,
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        iconColor: Color? = nil,
        autoDismissDelay: TimeInterval = 2.0
    ) {
        LoggingService.shared.info("ToastManager.update called for id: \(id), title: \(title)", category: .general)
        LoggingService.shared.info("Active toasts: \(self.activeToasts.map { $0.id })", category: .general)

        guard let index = activeToasts.firstIndex(where: { $0.id == id }) else {
            LoggingService.shared.warning("Cannot update toast \(id) - not found in active toasts", category: .general)
            return
        }

        LoggingService.shared.info("Found toast at index \(index), updating...", category: .general)

        // Update the toast
        withAnimation(.easeInOut(duration: 0.2)) {
            activeToasts[index].title = title
            activeToasts[index].subtitle = subtitle
            activeToasts[index].icon = icon
            activeToasts[index].iconColor = iconColor
        }

        LoggingService.shared.info("Updated toast: \(title), scheduling dismiss in \(autoDismissDelay) seconds", category: .general)

        // Cancel any existing dismiss task and schedule new one
        dismissTasks[id]?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(autoDismissDelay))
            guard !Task.isCancelled else { return }
            LoggingService.shared.info("Auto-dismissing toast after update: \(id)", category: .general)
            self?.dismissInternal(id: id, animated: true)
        }
        dismissTasks[id] = task
    }

    // MARK: - Player Scope Convenience Methods

    /// Show a loading toast (player-only scope, longer auto-dismiss delay).
    @discardableResult
    func showPlayerLoading(_ title: String, subtitle: String? = nil) -> UUID {
        show(
            scopes: [.player],
            category: .loading,
            title: title,
            subtitle: subtitle,
            icon: nil, // Will show ProgressView
            iconColor: nil,
            autoDismissDelay: 30.0 // Long timeout for loading states
        )
    }

    /// Show a retry toast (player-only scope).
    @discardableResult
    func showPlayerRetry(_ title: String, subtitle: String? = nil) -> UUID {
        show(
            scopes: [.player],
            category: .retry,
            title: title,
            subtitle: subtitle,
            icon: "arrow.clockwise",
            iconColor: .orange,
            autoDismissDelay: 5.0
        )
    }

    /// Show an error toast (player-only scope).
    @discardableResult
    func showPlayerError(_ title: String, subtitle: String? = nil) -> UUID {
        show(
            scopes: [.player],
            category: .error,
            title: title,
            subtitle: subtitle,
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            autoDismissDelay: 5.0
        )
    }

    // MARK: - General Convenience Methods

    /// Show an error toast (shows in player if visible, otherwise main).
    @discardableResult
    func showError(_ title: String, subtitle: String? = nil) -> UUID {
        show(
            category: .error,
            title: title,
            subtitle: subtitle,
            icon: "exclamationmark.triangle.fill",
            iconColor: .red,
            autoDismissDelay: 5.0
        )
    }

    /// Show a success toast (shows in player if visible, otherwise main).
    @discardableResult
    func showSuccess(_ title: String, subtitle: String? = nil) -> UUID {
        show(
            category: .success,
            title: title,
            subtitle: subtitle,
            icon: "checkmark.circle.fill",
            iconColor: .green,
            autoDismissDelay: 2.0
        )
    }

    /// Show an info toast (shows in player if visible, otherwise main).
    @discardableResult
    func showInfo(_ title: String, subtitle: String? = nil) -> UUID {
        show(
            category: .info,
            title: title,
            subtitle: subtitle,
            icon: "info.circle.fill",
            iconColor: .blue,
            autoDismissDelay: 3.0
        )
    }

    // MARK: - Dismiss Methods

    /// Dismiss a specific toast.
    func dismiss(id: UUID, animated: Bool = true) {
        dismissInternal(id: id, animated: animated)
    }

    /// Dismiss all toasts in a category (across all scopes).
    func dismissCategory(_ category: ToastCategory) {
        let toastsToDismiss = activeToasts.filter { $0.category == category }
        for toast in toastsToDismiss {
            dismissInternal(id: toast.id, animated: true)
        }
    }

    /// Dismiss all toasts in a category for a specific active scope.
    func dismissCategory(_ category: ToastCategory, scope: ToastScope) {
        let toastsToDismiss = activeToasts.filter { $0.category == category && $0.activeScope == scope }
        for toast in toastsToDismiss {
            dismissInternal(id: toast.id, animated: true)
        }
    }

    /// Dismiss all toasts in a specific active scope.
    func dismissScope(_ scope: ToastScope) {
        let toastsToDismiss = activeToasts.filter { $0.activeScope == scope }
        for toast in toastsToDismiss {
            dismissInternal(id: toast.id, animated: true)
        }
    }

    /// Dismiss all toasts.
    func dismissAll() {
        for task in dismissTasks.values {
            task.cancel()
        }
        dismissTasks.removeAll()

        withAnimation(.easeInOut(duration: 0.25)) {
            activeToasts.removeAll()
        }
    }

    // MARK: - Private

    private func dismissInternal(id: UUID, animated: Bool) {
        dismissTasks[id]?.cancel()
        dismissTasks.removeValue(forKey: id)

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                activeToasts.removeAll { $0.id == id }
            }
        } else {
            activeToasts.removeAll { $0.id == id }
        }

        LoggingService.shared.info("Dismissed toast: \(id)", category: .general)
    }

    private func scheduleAutoDismiss(for toast: Toast) {
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(toast.autoDismissDelay))
            guard !Task.isCancelled else { return }
            self?.dismissInternal(id: toast.id, animated: true)
        }
        dismissTasks[toast.id] = task
    }
}
