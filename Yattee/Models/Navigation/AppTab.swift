//
//  AppTab.swift
//  Yattee
//
//  Main app tab definitions.
//

import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case subscriptions
    case search
    #if os(tvOS)
    case settings
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "tabs.home")
        case .subscriptions: return String(localized: "tabs.subscriptions")
        case .search: return String(localized: "tabs.search")
        #if os(tvOS)
        case .settings: return String(localized: "tabs.settings")
        #endif
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .subscriptions: return "play.square.stack.fill"
        case .search: return "magnifyingglass"
        #if os(tvOS)
        case .settings: return "gearshape"
        #endif
        }
    }

    /// SidebarItem equivalent for UnifiedTabView navigation.
    var sidebarItem: SidebarItem {
        switch self {
        case .home: return .home
        case .subscriptions: return .subscriptionsFeed
        case .search: return .search
        #if os(tvOS)
        case .settings: return .settings
        #endif
        }
    }
}
