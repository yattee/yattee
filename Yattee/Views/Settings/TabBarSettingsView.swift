//
//  TabBarSettingsView.swift
//  Yattee
//
//  Settings sheet for customizing tab bar navigation items.
//

import SwiftUI

struct TabBarSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    private var itemOrder: [TabBarItem] {
        settingsManager?.tabBarItemOrder ?? TabBarItem.allCases
    }

    private var itemVisibility: [TabBarItem: Bool] {
        settingsManager?.tabBarItemVisibility ?? [:]
    }

    private var startupTabBinding: Binding<SidebarMainItem> {
        Binding(
            get: { settingsManager?.tabBarStartupTab ?? .home },
            set: { settingsManager?.tabBarStartupTab = $0 }
        )
    }

    /// Valid startup tabs based on current visibility settings.
    private var validStartupTabs: [SidebarMainItem] {
        // Fixed tabs always available
        var tabs: [SidebarMainItem] = [.home, .search]

        // Add visible configurable tabs based on current settings
        for item in itemOrder where itemVisibility[item] ?? false {
            if let mainItem = SidebarMainItem(tabBarItem: item) {
                tabs.append(mainItem)
            }
        }

        return tabs
    }

    var body: some View {
        NavigationStack {
            List {
                startupSection
                configurableTabsSection
            }
            #if os(iOS) || os(tvOS)
            .environment(\.editMode, .constant(.active))
            #endif
            .navigationTitle(String(localized: "settings.tabBar.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Sections

    private var startupSection: some View {
        Section {
            Picker(String(localized: "settings.tabBar.startup.tab"), selection: startupTabBinding) {
                ForEach(validStartupTabs) { item in
                    Text(item.localizedTitle).tag(item)
                }
            }
        } header: {
            Text(String(localized: "settings.tabBar.startup.header"))
        } footer: {
            Text(String(localized: "settings.tabBar.startup.footer"))
        }
    }

    private var configurableTabsSection: some View {
        Section {
            ForEach(itemOrder) { item in
                #if os(tvOS)
                if item != .downloads {
                    TabBarItemRow(
                        icon: item.icon,
                        title: item.localizedTitle,
                        isVisible: itemBinding(for: item)
                    )
                }
                #else
                TabBarItemRow(
                    icon: item.icon,
                    title: item.localizedTitle,
                    isVisible: itemBinding(for: item)
                )
                #endif
            }
            .onMove { from, to in
                var order = itemOrder
                order.move(fromOffsets: from, toOffset: to)
                settingsManager?.tabBarItemOrder = order
            }
        } footer: {
            Text(String(localized: "settings.tabBar.fixedTabs.footer"))
        }
    }

    // MARK: - Helpers

    private func itemBinding(for item: TabBarItem) -> Binding<Bool> {
        Binding(
            get: { itemVisibility[item] ?? false },
            set: { newValue in
                guard let settings = settingsManager else { return }
                settings.tabBarItemVisibility[item] = newValue

                // Reset startup tab to Home if the hidden item was the startup tab
                if !newValue,
                   let mainItem = SidebarMainItem(tabBarItem: item),
                   settings.tabBarStartupTab == mainItem {
                    settings.tabBarStartupTab = .home
                }
            }
        )
    }
}

// MARK: - Tab Bar Item Row

private struct TabBarItemRow: View {
    let icon: String
    let title: String
    @Binding var isVisible: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Toggle("", isOn: $isVisible)
                .labelsHidden()
        }
    }
}

// MARK: - Preview

#Preview {
    TabBarSettingsView()
        .appEnvironment(.preview)
}
