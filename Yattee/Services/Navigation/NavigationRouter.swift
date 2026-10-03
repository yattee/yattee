//
//  NavigationRouter.swift
//  Yattee
//
//  Layout-independent navigation state: which section is selected and what is
//  pushed in each section's stack. The tab bar and the sidebar layouts both
//  render this state, so swapping between them (iPad Stage Manager resize,
//  iPhone Duo fold/unfold) keeps the user where they were.
//

import SwiftUI

@Observable
@MainActor
final class NavigationRouter {
    /// The selected section. Both the tab bar and the sidebar bind to this.
    var selection: SidebarItem = .home {
        didSet {
            guard selection != oldValue else { return }
            onSelectionChange?(selection)
        }
    }

    /// Pushed destinations per section, keyed by `SidebarItem.id` so that a
    /// renamed channel or playlist keeps its stack.
    private(set) var stacks: [String: [NavigationDestination]] = [:]

    /// Search field text, shared so it survives a layout swap.
    var searchText = ""

    /// Sidebar channels, playlists and sources. Owned here rather than by the
    /// sidebar layout so it is created and loaded once.
    let sidebarManager = SidebarManager()

    @ObservationIgnored private var hasAppliedStartupTab = false
    @ObservationIgnored private var isSidebarManagerConfigured = false

    /// Called after every selection change (Handoff updates).
    @ObservationIgnored var onSelectionChange: ((SidebarItem) -> Void)?

    // MARK: - Stacks

    func path(for item: SidebarItem) -> Binding<[NavigationDestination]> {
        let key = item.id
        return Binding(
            get: { self.stacks[key] ?? [] },
            set: { self.stacks[key] = $0 }
        )
    }

    func stack(for item: SidebarItem) -> [NavigationDestination] {
        stacks[item.id] ?? []
    }

    /// Pushes a destination onto the selected section's stack.
    func push(_ destination: NavigationDestination) {
        stacks[selection.id, default: []].append(destination)
    }

    func popToRoot(_ item: SidebarItem? = nil) {
        stacks[(item ?? selection).id] = []
    }

    func select(_ item: SidebarItem) {
        selection = item
    }

    // MARK: - Startup

    /// Applies the configured startup section once per app run. Later layout
    /// swaps keep the current selection instead of jumping back to it.
    ///
    /// A destination pushed before the first layout appeared (a cold-launch
    /// deep link or Handoff) wins over the startup preference.
    func applyStartupTabIfNeeded(_ startupTab: SidebarMainItem) {
        guard !hasAppliedStartupTab else { return }
        hasAppliedStartupTab = true
        guard stack(for: selection).isEmpty else { return }
        selection = startupTab.sidebarItem
    }

    func configureSidebarManagerIfNeeded(_ appEnvironment: AppEnvironment) {
        guard !isSidebarManagerConfigured else { return }
        isSidebarManagerConfigured = true
        sidebarManager.configure(
            dataManager: appEnvironment.dataManager,
            settingsManager: appEnvironment.settingsManager,
            mediaSourcesManager: appEnvironment.mediaSourcesManager,
            instancesManager: appEnvironment.instancesManager,
            accountsManager: appEnvironment.accountsManager,
            subscriptionService: appEnvironment.subscriptionService,
            remotePlaylistsCache: appEnvironment.remotePlaylistsCache,
            contextValidator: appEnvironment.dataContextValidator
        )
    }

    // MARK: - Layout Mapping

    /// Makes the selection one the current layout can show.
    ///
    /// When the selected section has no tab or row of its own in this layout
    /// (a sidebar channel shown in the tab bar, a tab hidden by customization),
    /// the user lands on the closest section that can host it, with the
    /// section's own screen pushed first and its stack kept after it.
    ///
    /// - Parameters:
    ///   - isAvailable: whether the layout shows `item` as a tab or row.
    ///   - instance: resolves an instance ID for `.instance` items.
    func ensureSelectionIsAvailable(
        isAvailable: (SidebarItem) -> Bool,
        instance: (UUID) -> Instance? = { _ in nil }
    ) {
        let current = selection
        guard !isAvailable(current) else { return }

        let host: SidebarItem
        let root: NavigationDestination?
        switch current {
        case .channel(let channelID, _, let source):
            host = isAvailable(.subscriptionsFeed) ? .subscriptionsFeed : .home
            root = .channel(channelID, source)
        case .playlist, .remotePlaylist:
            host = isAvailable(.playlistsList) ? .playlistsList : .home
            root = current.navigationDestination()
        case .mediaSource(let id, _, _):
            host = isAvailable(.sources) ? .sources : .home
            root = .mediaSource(id)
        case .instance(let id, _, _):
            host = isAvailable(.sources) ? .sources : .home
            root = instance(id).map { .instanceBrowse($0) }
        case .sources:
            host = .home
            root = .mediaSources
        default:
            host = .home
            root = current.navigationDestination()
        }

        let carried = stack(for: current)
        if let root {
            stacks[host.id] = [root] + carried
        }
        stacks[current.id] = []
        selection = host
    }
}
