//
//  View+ZoomTransition.swift
//  Yattee
//
//  View modifiers for iOS 18 zoom navigation transitions.
//  Note: Zoom transitions are only available on iOS. On other platforms,
//  these modifiers have no effect but are still safe to use.
//

import SwiftUI

// MARK: - Environment Keys

/// Environment key to pass the navigation transition namespace through the view hierarchy.
private struct ZoomTransitionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

/// Environment key to control whether zoom transitions are enabled.
private struct ZoomTransitionsEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    /// The namespace used for zoom navigation transitions.
    var zoomTransitionNamespace: Namespace.ID? {
        get { self[ZoomTransitionNamespaceKey.self] }
        set { self[ZoomTransitionNamespaceKey.self] = newValue }
    }

    /// Whether zoom transitions are enabled. Defaults to true.
    var zoomTransitionsEnabled: Bool {
        get { self[ZoomTransitionsEnabledKey.self] }
        set { self[ZoomTransitionsEnabledKey.self] = newValue }
    }
}

// MARK: - Transition Source Modifier

/// View modifier that marks a view as the source for a zoom navigation transition.
///
/// Apply this to a NavigationLink or the view it wraps. When the user navigates
/// to the destination, the view will animate with a zoom effect from this source.
/// Note: Only has an effect on iOS. On macOS and tvOS, returns the content unchanged.
struct ZoomTransitionSourceModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.zoomTransitionNamespace) private var namespace
    @Environment(\.zoomTransitionsEnabled) private var zoomTransitionsEnabled

    func body(content: Content) -> some View {
        #if os(iOS)
        if zoomTransitionsEnabled, let namespace {
            content
                .matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Transition Destination Modifier

/// View modifier that applies the zoom navigation transition to a destination view.
///
/// Apply this to the destination view of a NavigationLink. When navigating to this view,
/// it will animate with a zoom effect from the matched source.
/// Note: Only has an effect on iOS. On macOS and tvOS, returns the content unchanged.
struct ZoomTransitionDestinationModifier<ID: Hashable>: ViewModifier {
    let id: ID
    @Environment(\.zoomTransitionNamespace) private var namespace
    @Environment(\.zoomTransitionsEnabled) private var zoomTransitionsEnabled

    func body(content: Content) -> some View {
        #if os(iOS)
        if zoomTransitionsEnabled, let namespace {
            content
                .navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - View Extensions

extension View {
    /// Marks this view as the source for a zoom navigation transition.
    ///
    /// Apply this modifier to a NavigationLink or the view it wraps.
    /// The id must match the destination's transition id for the zoom effect to work.
    ///
    /// Note: Only has an effect on iOS. Safe to use on all platforms.
    ///
    /// - Parameter id: Unique identifier for the transition (e.g., video.id, channel.id).
    /// - Returns: A view that serves as the source for the zoom transition.
    ///
    /// Example:
    /// ```swift
    /// NavigationLink(value: NavigationDestination.channel(channel.id, source)) {
    ///     ChannelRowView(channel: channel)
    /// }
    /// .zoomTransitionSource(id: channel.id)
    /// ```
    func zoomTransitionSource<ID: Hashable>(id: ID) -> some View {
        modifier(ZoomTransitionSourceModifier(id: id))
    }

    /// Applies the zoom navigation transition to this destination view.
    ///
    /// Apply this modifier to the destination view of a NavigationLink.
    /// The id must match the source's transition id for the zoom effect to work.
    ///
    /// Note: Only has an effect on iOS. Safe to use on all platforms.
    ///
    /// - Parameter id: Unique identifier matching the source's id.
    /// - Returns: A view with the zoom transition applied.
    ///
    /// Example:
    /// ```swift
    /// ChannelView(channel: channel)
    ///     .zoomTransitionDestination(id: channel.id)
    /// ```
    func zoomTransitionDestination<ID: Hashable>(id: ID) -> some View {
        modifier(ZoomTransitionDestinationModifier(id: id))
    }

    /// Injects the zoom transition namespace into the environment.
    ///
    /// Apply this modifier to a NavigationStack to enable zoom transitions
    /// for all NavigationLinks within that stack.
    ///
    /// - Parameter namespace: The namespace to use for matched transitions.
    /// - Returns: A view with the namespace injected into the environment.
    ///
    /// Example:
    /// ```swift
    /// @Namespace private var zoomTransition
    ///
    /// NavigationStack {
    ///     ContentView()
    /// }
    /// .zoomTransitionNamespace(zoomTransition)
    /// ```
    func zoomTransitionNamespace(_ namespace: Namespace.ID) -> some View {
        environment(\.zoomTransitionNamespace, namespace)
    }

    /// Injects the zoom transition namespace into the environment (optional overload).
    ///
    /// If the namespace is nil, the view is returned unchanged.
    ///
    /// - Parameter namespace: The optional namespace to use for matched transitions.
    /// - Returns: A view with the namespace injected into the environment, or unchanged if nil.
    @ViewBuilder
    func zoomTransitionNamespace(_ namespace: Namespace.ID?) -> some View {
        if let namespace {
            environment(\.zoomTransitionNamespace, namespace)
        } else {
            self
        }
    }

    /// Sets whether zoom transitions are enabled.
    ///
    /// Apply this at a high level in the view hierarchy (e.g., ContentView) to control
    /// whether zoom navigation transitions are applied throughout the app.
    ///
    /// - Parameter enabled: Whether zoom transitions should be enabled.
    /// - Returns: A view with the zoom transitions enabled state set.
    func zoomTransitionsEnabled(_ enabled: Bool) -> some View {
        environment(\.zoomTransitionsEnabled, enabled)
    }
}
