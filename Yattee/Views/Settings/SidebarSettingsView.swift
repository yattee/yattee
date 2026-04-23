//
//  SidebarSettingsView.swift
//  Yattee
//
//  Settings for customizing sidebar content on iOS 18+, macOS, and tvOS 18+.
//

import SwiftUI

struct SidebarSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    // Local state for main navigation editing (copied from settings on appear, saved on dismiss)
    @State private var mainItemOrder: [SidebarMainItem] = []
    @State private var mainItemVisibility: [SidebarMainItem: Bool] = [:]

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    // MARK: - Sources Bindings

    private var sourcesEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager?.sidebarSourcesEnabled ?? true },
            set: { settingsManager?.sidebarSourcesEnabled = $0 }
        )
    }

    private var sourceSortBinding: Binding<SidebarSourceSort> {
        Binding(
            get: { settingsManager?.sidebarSourceSort ?? .name },
            set: { settingsManager?.sidebarSourceSort = $0 }
        )
    }

    private var sourcesLimitEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager?.sidebarSourcesLimitEnabled ?? false },
            set: { settingsManager?.sidebarSourcesLimitEnabled = $0 }
        )
    }

    private var maxSourcesBinding: Binding<Int> {
        Binding(
            get: { settingsManager?.sidebarMaxSources ?? SettingsManager.defaultSidebarMaxSources },
            set: { settingsManager?.sidebarMaxSources = $0 }
        )
    }

    // MARK: - Channels Bindings

    private var maxChannelsBinding: Binding<Int> {
        Binding(
            get: { settingsManager?.sidebarMaxChannels ?? SettingsManager.defaultSidebarMaxChannels },
            set: { settingsManager?.sidebarMaxChannels = $0 }
        )
    }

    private var channelSortBinding: Binding<SidebarChannelSort> {
        Binding(
            get: { settingsManager?.sidebarChannelSort ?? .alphabetical },
            set: { settingsManager?.sidebarChannelSort = $0 }
        )
    }

    private var channelsLimitEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager?.sidebarChannelsLimitEnabled ?? true },
            set: { settingsManager?.sidebarChannelsLimitEnabled = $0 }
        )
    }

    private var channelsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager?.sidebarChannelsEnabled ?? true },
            set: { settingsManager?.sidebarChannelsEnabled = $0 }
        )
    }

    // MARK: - Playlists Bindings

    private var maxPlaylistsBinding: Binding<Int> {
        Binding(
            get: { settingsManager?.sidebarMaxPlaylists ?? SettingsManager.defaultSidebarMaxPlaylists },
            set: { settingsManager?.sidebarMaxPlaylists = $0 }
        )
    }

    private var playlistSortBinding: Binding<SidebarPlaylistSort> {
        Binding(
            get: { settingsManager?.sidebarPlaylistSort ?? .alphabetical },
            set: { settingsManager?.sidebarPlaylistSort = $0 }
        )
    }

    private var playlistsLimitEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager?.sidebarPlaylistsLimitEnabled ?? false },
            set: { settingsManager?.sidebarPlaylistsLimitEnabled = $0 }
        )
    }

    private var playlistsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settingsManager?.sidebarPlaylistsEnabled ?? true },
            set: { settingsManager?.sidebarPlaylistsEnabled = $0 }
        )
    }

    // MARK: - Startup Binding

    private var startupTabBinding: Binding<SidebarMainItem> {
        Binding(
            get: { settingsManager?.sidebarStartupTab ?? .home },
            set: { settingsManager?.sidebarStartupTab = $0 }
        )
    }

    /// Valid startup tabs based on current visibility settings.
    private var validStartupTabs: [SidebarMainItem] {
        // Filter main items by visibility (respecting required items and platform availability)
        let visibility = mainItemVisibility
        return mainItemOrder
            .filter { $0.isAvailableOnCurrentPlatform }
            .filter { $0.isRequired || (visibility[$0] ?? true) }
    }

    var body: some View {
        NavigationStack {
            List {
                startupSection
                mainNavigationSection
                sourcesSection
                channelsSection
                playlistsSection
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))
            #endif
            #if !os(tvOS)
            .navigationTitle(String(localized: "settings.sidebar.title"))
            #endif
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                loadMainNavigationSettings()
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Startup Section

    private var startupSection: some View {
        Section {
            PlatformMenuPicker(String(localized: "settings.sidebar.startup.tab"), selection: startupTabBinding) {
                ForEach(validStartupTabs) { item in
                    Text(item.localizedTitle).tag(item)
                }
            }
        } header: {
            Text(String(localized: "settings.sidebar.startup.header"))
        } footer: {
            Text(String(localized: "settings.sidebar.startup.footer"))
        }
    }

    // MARK: - Main Navigation Section

    private var mainNavigationSection: some View {
        Section {
            #if os(tvOS)
            let availableItems = mainItemOrder.filter { $0.isAvailableOnCurrentPlatform }
            ForEach(Array(availableItems.enumerated()), id: \.element.id) { index, item in
                TVSidebarMainItemRow(
                    icon: item.icon,
                    title: item.localizedTitle,
                    isRequired: item.isRequired,
                    isVisible: mainItemBinding(for: item),
                    canMoveUp: index > 0,
                    canMoveDown: index < availableItems.count - 1,
                    onMoveUp: { moveMainItem(at: index, direction: -1) },
                    onMoveDown: { moveMainItem(at: index, direction: 1) }
                )
            }
            #else
            ForEach(mainItemOrder.filter { $0.isAvailableOnCurrentPlatform }) { item in
                SidebarMainItemRow(
                    icon: item.icon,
                    title: item.localizedTitle,
                    isRequired: item.isRequired,
                    isVisible: mainItemBinding(for: item)
                )
            }
            .onMove { from, to in
                // Filter to get only platform-available items for correct index mapping
                let availableItems = mainItemOrder.filter { $0.isAvailableOnCurrentPlatform }

                // Get the items being moved
                guard let fromIndex = from.first,
                      fromIndex < availableItems.count,
                      to <= availableItems.count else { return }

                let movedItem = availableItems[fromIndex]
                let targetItem = to < availableItems.count ? availableItems[to] : nil

                // Find actual indices in mainItemOrder
                guard let actualFromIndex = mainItemOrder.firstIndex(of: movedItem) else { return }

                // Remove from current position
                mainItemOrder.remove(at: actualFromIndex)

                // Find target position
                if let targetItem = targetItem,
                   let actualToIndex = mainItemOrder.firstIndex(of: targetItem) {
                    mainItemOrder.insert(movedItem, at: actualToIndex)
                } else {
                    mainItemOrder.append(movedItem)
                }

                // Save immediately
                saveMainNavigationSettings()
            }
            #endif
        } header: {
            Text(String(localized: "settings.sidebar.mainNavigation.header"))
        } footer: {
            Text(String(localized: "settings.sidebar.mainNavigation.footer"))
        }
    }

    #if os(tvOS)
    private func moveMainItem(at index: Int, direction: Int) {
        let available = mainItemOrder.filter { $0.isAvailableOnCurrentPlatform }
        let newIndex = index + direction
        guard index >= 0, index < available.count,
              newIndex >= 0, newIndex < available.count else { return }

        let movedItem = available[index]
        let neighborItem = available[newIndex]

        guard let fromActual = mainItemOrder.firstIndex(of: movedItem),
              let toActual = mainItemOrder.firstIndex(of: neighborItem) else { return }

        mainItemOrder.swapAt(fromActual, toActual)
        saveMainNavigationSettings()
    }
    #endif

    private func mainItemBinding(for item: SidebarMainItem) -> Binding<Bool> {
        Binding(
            get: { mainItemVisibility[item] ?? true },
            set: { newValue in
                mainItemVisibility[item] = newValue
                saveMainNavigationSettings()

                // Reset startup tab to Home if the hidden item was the startup tab
                if !newValue, settingsManager?.sidebarStartupTab == item {
                    settingsManager?.sidebarStartupTab = .home
                }
            }
        )
    }

    // MARK: - Main Navigation Data Management

    private func loadMainNavigationSettings() {
        guard let settings = settingsManager else { return }
        mainItemOrder = settings.sidebarMainItemOrder
        mainItemVisibility = settings.sidebarMainItemVisibility
    }

    private func saveMainNavigationSettings() {
        guard let settings = settingsManager else { return }
        settings.sidebarMainItemOrder = mainItemOrder
        settings.sidebarMainItemVisibility = mainItemVisibility
        notifySidebarSettingsChanged()
    }

    // MARK: - Sections

    private var sourcesSection: some View {
        Section {
            // Show in Sidebar toggle
            Toggle(String(localized: "settings.sidebar.showInSidebar"), isOn: sourcesEnabledBinding)
                .onChange(of: sourcesEnabledBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }

            // Source sort order
            PlatformMenuPicker(String(localized: "settings.sidebar.sourceSort"), selection: sourceSortBinding) {
                ForEach(SidebarSourceSort.allCases) { sort in
                    Text(sort.localizedTitle).tag(sort)
                }
            }
            .disabled(!sourcesEnabledBinding.wrappedValue)
            .onChange(of: sourceSortBinding.wrappedValue) {
                notifySidebarSettingsChanged()
            }

            // Limit sources toggle
            Toggle(String(localized: "settings.sidebar.sourcesLimitEnabled"), isOn: sourcesLimitEnabledBinding)
                .disabled(!sourcesEnabledBinding.wrappedValue)
                .onChange(of: sourcesLimitEnabledBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }

            // Max sources (only shown when limit is enabled)
            if sourcesLimitEnabledBinding.wrappedValue {
                #if os(tvOS)
                // tvOS uses Picker instead of Slider (Slider/Stepper unavailable)
                PlatformMenuPicker(String(localized: "settings.sidebar.maxSources"), selection: maxSourcesBinding) {
                    ForEach([5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .disabled(!sourcesEnabledBinding.wrappedValue)
                .onChange(of: maxSourcesBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }
                #else
                // Max sources slider
                HStack {
                    Text(String(localized: "settings.sidebar.maxSources"))
                    Spacer()
                    Text("\(maxSourcesBinding.wrappedValue)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .foregroundStyle(sourcesEnabledBinding.wrappedValue ? .primary : .secondary)

                Slider(
                    value: Binding(
                        get: { Double(maxSourcesBinding.wrappedValue) },
                        set: { maxSourcesBinding.wrappedValue = Int($0) }
                    ),
                    in: 5...100,
                    step: 5
                ) { editing in
                    if !editing {
                        notifySidebarSettingsChanged()
                    }
                }
                .disabled(!sourcesEnabledBinding.wrappedValue)
                #endif
            }
        } header: {
            Text(String(localized: "settings.sidebar.sources.header"))
        } footer: {
            Text(String(localized: "settings.sidebar.sources.footer"))
        }
    }

    private var channelsSection: some View {
        Section {
            // Show in Sidebar toggle (first)
            Toggle(String(localized: "settings.sidebar.showInSidebar"), isOn: channelsEnabledBinding)
                .onChange(of: channelsEnabledBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }

            // Channel sort order
            PlatformMenuPicker(String(localized: "settings.sidebar.channelSort"), selection: channelSortBinding) {
                ForEach(SidebarChannelSort.allCases.filter { $0 != .custom }) { sort in
                    Text(sort.localizedTitle).tag(sort)
                }
            }
            .disabled(!channelsEnabledBinding.wrappedValue)
            .onChange(of: channelSortBinding.wrappedValue) {
                notifySidebarSettingsChanged()
            }

            // Limit channels toggle
            Toggle(String(localized: "settings.sidebar.channelsLimitEnabled"), isOn: channelsLimitEnabledBinding)
                .disabled(!channelsEnabledBinding.wrappedValue)
                .onChange(of: channelsLimitEnabledBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }

            // Max channels (only shown when limit is enabled)
            if channelsLimitEnabledBinding.wrappedValue {
                #if os(tvOS)
                // tvOS uses Picker instead of Slider (Slider/Stepper unavailable)
                PlatformMenuPicker(String(localized: "settings.sidebar.maxChannels"), selection: maxChannelsBinding) {
                    ForEach([5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 70, 80, 90, 100], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .disabled(!channelsEnabledBinding.wrappedValue)
                .onChange(of: maxChannelsBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }
                #else
                // Max channels slider
                HStack {
                    Text(String(localized: "settings.sidebar.maxChannels"))
                    Spacer()
                    Text("\(maxChannelsBinding.wrappedValue)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .foregroundStyle(channelsEnabledBinding.wrappedValue ? .primary : .secondary)

                Slider(
                    value: Binding(
                        get: { Double(maxChannelsBinding.wrappedValue) },
                        set: { maxChannelsBinding.wrappedValue = Int($0) }
                    ),
                    in: 5...100,
                    step: 5
                ) { editing in
                    if !editing {
                        notifySidebarSettingsChanged()
                    }
                }
                .disabled(!channelsEnabledBinding.wrappedValue)
                #endif
            }
        } header: {
            Text(String(localized: "settings.sidebar.channels.header"))
        } footer: {
            Text(String(localized: "settings.sidebar.channels.footer"))
        }
    }

    private var playlistsSection: some View {
        Section {
            // Show in Sidebar toggle (first)
            Toggle(String(localized: "settings.sidebar.showInSidebar"), isOn: playlistsEnabledBinding)
                .onChange(of: playlistsEnabledBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }

            // Playlist sort order
            PlatformMenuPicker(String(localized: "settings.sidebar.playlistSort"), selection: playlistSortBinding) {
                ForEach(SidebarPlaylistSort.allCases) { sort in
                    Text(sort.localizedTitle).tag(sort)
                }
            }
            .disabled(!playlistsEnabledBinding.wrappedValue)
            .onChange(of: playlistSortBinding.wrappedValue) {
                notifySidebarSettingsChanged()
            }

            // Limit playlists toggle
            Toggle(String(localized: "settings.sidebar.playlistsLimitEnabled"), isOn: playlistsLimitEnabledBinding)
                .disabled(!playlistsEnabledBinding.wrappedValue)
                .onChange(of: playlistsLimitEnabledBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }

            // Max playlists (only shown when limit is enabled)
            if playlistsLimitEnabledBinding.wrappedValue {
                #if os(tvOS)
                // tvOS uses Picker instead of Slider (Slider/Stepper unavailable)
                PlatformMenuPicker(String(localized: "settings.sidebar.maxPlaylists"), selection: maxPlaylistsBinding) {
                    ForEach([5, 10, 15, 20, 25, 30], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .disabled(!playlistsEnabledBinding.wrappedValue)
                .onChange(of: maxPlaylistsBinding.wrappedValue) {
                    notifySidebarSettingsChanged()
                }
                #else
                // Max playlists slider
                HStack {
                    Text(String(localized: "settings.sidebar.maxPlaylists"))
                    Spacer()
                    Text("\(maxPlaylistsBinding.wrappedValue)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .foregroundStyle(playlistsEnabledBinding.wrappedValue ? .primary : .secondary)

                Slider(
                    value: Binding(
                        get: { Double(maxPlaylistsBinding.wrappedValue) },
                        set: { maxPlaylistsBinding.wrappedValue = Int($0) }
                    ),
                    in: 5...30,
                    step: 5
                ) { editing in
                    if !editing {
                        notifySidebarSettingsChanged()
                    }
                }
                .disabled(!playlistsEnabledBinding.wrappedValue)
                #endif
            }
        } header: {
            Text(String(localized: "settings.sidebar.playlists.header"))
        } footer: {
            Text(String(localized: "settings.sidebar.playlists.footer"))
        }
    }

    // MARK: - Notifications

    private func notifySidebarSettingsChanged() {
        NotificationCenter.default.post(name: .sidebarSettingsDidChange, object: nil)
    }
}

// MARK: - Sidebar Main Item Row

private struct SidebarMainItemRow: View {
    let icon: String
    let title: String
    let isRequired: Bool
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
                .disabled(isRequired)
        }
    }
}

// MARK: - tvOS Sidebar Main Item Row

#if os(tvOS)
private struct TVSidebarMainItemRow: View {
    let icon: String
    let title: String
    let isRequired: Bool
    @Binding var isVisible: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 4) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(canMoveUp ? .primary : .tertiary)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(TVSidebarCompactButtonStyle())
                .disabled(!canMoveUp)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(canMoveDown ? .primary : .tertiary)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(TVSidebarCompactButtonStyle())
                .disabled(!canMoveDown)
            }

            Button {
                guard !isRequired else { return }
                isVisible.toggle()
            } label: {
                HStack {
                    Image(systemName: icon)
                        .frame(width: 24)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isRequired ? .secondary : (isVisible ? .green : .secondary))
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TVFormRowButtonStyle())
            .disabled(isRequired)
        }
        .padding(.vertical, 4)
    }
}

private struct TVSidebarCompactButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused ? Color.white.opacity(0.2) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : (isFocused ? 1.1 : 1.0))
            .animation(.easeInOut(duration: 0.1), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
#endif

// MARK: - Preview

#Preview {
    SidebarSettingsView()
        .appEnvironment(.preview)
}
