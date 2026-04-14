//
//  HomeSettingsView.swift
//  Yattee
//
//  Settings sheet for customizing the Home view layout.
//

import SwiftUI

struct HomeSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    // Local state for editing (copied from settings on appear, saved on dismiss)
    @State private var shortcutLayout: HomeShortcutLayout = .cards
    @State private var shortcutOrder: [HomeShortcutItem] = []
    @State private var shortcutVisibility: [HomeShortcutItem: Bool] = [:]
    @State private var sectionOrder: [HomeSectionItem] = []
    @State private var sectionVisibility: [HomeSectionItem: Bool] = [:]
    @State private var sectionItemsLimit: Int = 5
    
    // Available items (not yet added to Home)
    @State private var availableShortcutsByInstance: [(instance: Instance, cards: [HomeShortcutItem])] = []
    @State private var availableSectionsByInstance: [(instance: Instance, sections: [HomeSectionItem])] = []
    @State private var availableShortcutsByMediaSource: [(source: MediaSource, cards: [HomeShortcutItem])] = []
    @State private var availableSectionsByMediaSource: [(source: MediaSource, sections: [HomeSectionItem])] = []
    
    // Edit mode for delete functionality
    @State private var isEditMode = false

    private var settingsManager: SettingsManager? { appEnvironment?.settingsManager }

    var body: some View {
        List {
            #if !os(tvOS)
            shortcutsSection
            availableShortcutsSection
            #endif
            sectionsSection
            availableSectionsSection
            itemsLimitSection
        }
        #if os(iOS)
        .environment(\.editMode, isEditMode ? .constant(.active) : .constant(.inactive))
        #endif
        .navigationTitle(String(localized: "home.settings.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadSettings()
        }
        .onDisappear {
            saveSettings()
        }
    }

    // MARK: - Sections

    private var shortcutsSection: some View {
        Section {
            #if !os(tvOS)
            // Layout picker (List vs Cards)
            Picker(String(localized: "home.settings.shortcuts.layout"), selection: $shortcutLayout) {
                ForEach(HomeShortcutLayout.allCases, id: \.self) { layout in
                    Label(layout.displayName, systemImage: layout.systemImage)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            #endif

            #if os(tvOS)
            ForEach(Array(shortcutOrder.enumerated()), id: \.element.id) { index, card in
                if card != .downloads {
                    TVHomeItemRow(
                        icon: card.icon,
                        title: card.localizedTitle,
                        isVisible: shortcutBinding(for: card),
                        canMoveUp: index > 0 && shortcutOrder[index - 1] != .downloads,
                        canMoveDown: index < shortcutOrder.count - 1,
                        onMoveUp: { moveShortcut(at: index, direction: -1) },
                        onMoveDown: { moveShortcut(at: index, direction: 1) },
                        canDelete: canDelete(shortcut: card),
                        onDelete: { removeShortcut(card) }
                    )
                }
            }
            #else
            ForEach(shortcutOrder) { card in
                shortcutRowView(for: card)
            }
            .onMove { from, to in
                shortcutOrder.move(fromOffsets: from, toOffset: to)
            }
            #endif
        } header: {
            Text(String(localized: "home.settings.shortcuts.header"))
        }
    }
    
    private var availableShortcutsSection: some View {
        Section {
            if availableShortcutsByInstance.isEmpty && availableShortcutsByMediaSource.isEmpty {
                Text(String(localized: "home.settings.availableShortcuts.empty"))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(availableShortcutsByInstance, id: \.instance.id) { item in
                    ForEach(item.cards) { card in
                        availableShortcutRow(for: card, instance: item.instance)
                    }
                }
                ForEach(availableShortcutsByMediaSource, id: \.source.id) { item in
                    ForEach(item.cards) { card in
                        availableMediaSourceShortcutRow(for: card, source: item.source)
                    }
                }
            }
        } header: {
            Text(String(localized: "home.settings.availableShortcuts.header"))
        } footer: {
            Text(String(localized: "home.settings.availableShortcuts.footer"))
        }
    }

    private var sectionsSection: some View {
        Section {
            #if os(tvOS)
            ForEach(Array(sectionOrder.enumerated()), id: \.element.id) { index, section in
                if section != .downloads {
                    TVHomeItemRow(
                        icon: section.icon,
                        title: section.localizedTitle,
                        isVisible: sectionBinding(for: section),
                        canMoveUp: index > 0 && sectionOrder[index - 1] != .downloads,
                        canMoveDown: index < sectionOrder.count - 1,
                        onMoveUp: { moveSection(at: index, direction: -1) },
                        onMoveDown: { moveSection(at: index, direction: 1) },
                        canDelete: canDelete(section: section),
                        onDelete: { removeSection(section) }
                    )
                }
            }
            #else
            ForEach(sectionOrder) { section in
                sectionRowView(for: section)
            }
            .onMove { from, to in
                sectionOrder.move(fromOffsets: from, toOffset: to)
            }
            #endif
        } header: {
            Text(String(localized: "home.settings.sections.header"))
        } footer: {
            Text(String(localized: "home.settings.sections.footer"))
        }
    }
    
    private var availableSectionsSection: some View {
        Section {
            if availableSectionsByInstance.isEmpty && availableSectionsByMediaSource.isEmpty {
                Text(String(localized: "home.settings.availableSections.empty"))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(availableSectionsByInstance, id: \.instance.id) { item in
                    ForEach(item.sections) { section in
                        availableSectionRow(for: section, instance: item.instance)
                    }
                }
                ForEach(availableSectionsByMediaSource, id: \.source.id) { item in
                    ForEach(item.sections) { section in
                        availableMediaSourceSectionRow(for: section, source: item.source)
                    }
                }
            }
        } header: {
            Text(String(localized: "home.settings.availableSections.header"))
        } footer: {
            Text(String(localized: "home.settings.availableSections.footer"))
        }
    }

    #if os(tvOS)
    private func moveShortcut(at index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < shortcutOrder.count else { return }
        shortcutOrder.swapAt(index, newIndex)
    }

    private func moveSection(at index: Int, direction: Int) {
        let newIndex = index + direction
        guard newIndex >= 0, newIndex < sectionOrder.count else { return }
        sectionOrder.swapAt(index, newIndex)
    }
    #endif

    private var itemsLimitSection: some View {
        Section {
            #if os(tvOS)
            HStack {
                Text(String(localized: "home.settings.itemsLimit"))
                Spacer()
                Button {
                    if sectionItemsLimit > 1 { sectionItemsLimit -= 1 }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(TVSettingsButtonStyle())
                Text("\(sectionItemsLimit)")
                    .monospacedDigit()
                Button {
                    if sectionItemsLimit < 20 { sectionItemsLimit += 1 }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(TVSettingsButtonStyle())
            }
            #else
            Stepper(value: $sectionItemsLimit, in: 1...20) {
                HStack {
                    Text(String(localized: "home.settings.itemsLimit"))
                    Spacer()
                    Text("\(sectionItemsLimit)")
                        .foregroundStyle(.secondary)
                }
            }
            #endif
        }
    }

    // MARK: - Bindings

    private func shortcutBinding(for card: HomeShortcutItem) -> Binding<Bool> {
        Binding(
            get: { shortcutVisibility[card] ?? true },
            set: { shortcutVisibility[card] = $0 }
        )
    }

    private func sectionBinding(for section: HomeSectionItem) -> Binding<Bool> {
        Binding(
            get: { sectionVisibility[section] ?? false },
            set: { sectionVisibility[section] = $0 }
        )
    }

    // MARK: - Data Management

    private func loadSettings() {
        guard let settings = settingsManager,
              let env = appEnvironment else { return }

        shortcutLayout = settings.homeShortcutLayout
        shortcutOrder = settings.homeShortcutOrder
        shortcutVisibility = settings.homeShortcutVisibility
        sectionOrder = settings.homeSectionOrder
        sectionVisibility = settings.homeSectionVisibility
        sectionItemsLimit = settings.homeSectionItemsLimit

        // Load available items
        let instances = env.instancesManager.instances
        availableShortcutsByInstance = settings.allAvailableShortcuts(instances: instances)
        availableSectionsByInstance = settings.allAvailableSections(instances: instances)

        let sources = env.mediaSourcesManager.sources
        availableShortcutsByMediaSource = settings.allAvailableMediaSourceShortcuts(sources: sources)
        availableSectionsByMediaSource = settings.allAvailableMediaSourceSections(sources: sources)
    }

    private func saveSettings() {
        guard let settings = settingsManager else { return }
        settings.homeShortcutLayout = shortcutLayout
        settings.homeShortcutOrder = shortcutOrder
        settings.homeShortcutVisibility = shortcutVisibility
        settings.homeSectionOrder = sectionOrder
        settings.homeSectionVisibility = sectionVisibility
        settings.homeSectionItemsLimit = sectionItemsLimit
    }

    // MARK: - Available Item Management
    
    private func addShortcut(_ card: HomeShortcutItem) {
        // Add to local state
        if !shortcutOrder.contains(where: { $0.id == card.id }) {
            shortcutOrder.append(card)
            shortcutVisibility[card] = true  // Visible by default
        }
        
        // Persist to settings
        switch card {
        case .instanceContent(let instanceID, let contentType):
            settingsManager?.addToHome(instanceID: instanceID, contentType: contentType, asCard: true)
        case .mediaSource(let sourceID):
            settingsManager?.addToHome(sourceID: sourceID, asCard: true)
        default:
            break
        }
        
        // Reload available items
        loadSettings()
    }
    
    private func addSection(_ section: HomeSectionItem) {
        // Add to local state
        if !sectionOrder.contains(where: { $0.id == section.id }) {
            sectionOrder.append(section)
            sectionVisibility[section] = true  // Visible by default
        }
        
        // Persist to settings
        switch section {
        case .instanceContent(let instanceID, let contentType):
            settingsManager?.addToHome(instanceID: instanceID, contentType: contentType, asCard: false)
        case .mediaSource(let sourceID):
            settingsManager?.addToHome(sourceID: sourceID, asCard: false)
        default:
            break
        }
        
        // Reload available items
        loadSettings()
    }
    
    private func removeShortcut(_ card: HomeShortcutItem) {
        // Remove from local state
        shortcutOrder.removeAll { $0.id == card.id }
        shortcutVisibility.removeValue(forKey: card)
        
        // Persist to settings
        switch card {
        case .instanceContent(let instanceID, let contentType):
            settingsManager?.removeFromHome(instanceID: instanceID, contentType: contentType)
        case .mediaSource(let sourceID):
            settingsManager?.removeFromHome(sourceID: sourceID)
        default:
            break
        }
        
        // Reload available items
        loadSettings()
    }
    
    private func removeSection(_ section: HomeSectionItem) {
        // Remove from local state
        sectionOrder.removeAll { $0.id == section.id }
        sectionVisibility.removeValue(forKey: section)
        
        // Persist to settings
        switch section {
        case .instanceContent(let instanceID, let contentType):
            settingsManager?.removeFromHome(instanceID: instanceID, contentType: contentType)
        case .mediaSource(let sourceID):
            settingsManager?.removeFromHome(sourceID: sourceID)
        default:
            break
        }
        
        // Reload available items
        loadSettings()
    }
    
    private func canDelete(shortcut: HomeShortcutItem) -> Bool {
        if case .instanceContent = shortcut {
            return true
        }
        if case .mediaSource = shortcut {
            return true
        }
        return false
    }
    
    private func canDelete(section: HomeSectionItem) -> Bool {
        if case .instanceContent = section {
            return true
        }
        if case .mediaSource = section {
            return true
        }
        return false
    }

    // MARK: - Card and Section Row Views

    @ViewBuilder
    private func shortcutRowView(for card: HomeShortcutItem) -> some View {
        switch card {
        case .instanceContent(let instanceID, let contentType):
            if let instance = instanceFromID(instanceID) {
                let isDisabled = !instance.isEnabled || (contentType == .feed && !isLoggedIn(instance))
                
                HomeItemRow(
                    icon: contentType.icon,
                    title: "\(instance.displayName) - \(contentType.localizedTitle)",
                    isVisible: shortcutBinding(for: card),
                    isDisabled: isDisabled,
                    disabledReason: disabledReason(instance: instance, contentType: contentType)
                )
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        removeShortcut(card)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                    .tint(.red)
                }
                #endif
                .contextMenu {
                    Button(role: .destructive) {
                        removeShortcut(card)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                }
            }
        case .mediaSource(let sourceID):
            if let source = appEnvironment?.mediaSourcesManager.sources.first(where: { $0.id == sourceID }) {
                let isDisabled = !source.isEnabled
                
                HomeItemRow(
                    icon: source.type.systemImage,
                    title: "\(source.name) (\(source.type.displayName))",
                    isVisible: shortcutBinding(for: card),
                    isDisabled: isDisabled,
                    disabledReason: isDisabled ? String(localized: "home.settings.sourceDisabled") : nil
                )
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        removeShortcut(card)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                    .tint(.red)
                }
                #endif
                .contextMenu {
                    Button(role: .destructive) {
                        removeShortcut(card)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                }
            }
        default:
            HomeItemRow(
                icon: card.icon,
                title: card.localizedTitle,
                isVisible: shortcutBinding(for: card)
            )
        }
    }

    @ViewBuilder
    private func sectionRowView(for section: HomeSectionItem) -> some View {
        switch section {
        case .instanceContent(let instanceID, let contentType):
            if let instance = instanceFromID(instanceID) {
                let isDisabled = !instance.isEnabled || (contentType == .feed && !isLoggedIn(instance))
                
                HomeItemRow(
                    icon: contentType.icon,
                    title: "\(instance.displayName) - \(contentType.localizedTitle)",
                    isVisible: sectionBinding(for: section),
                    isDisabled: isDisabled,
                    disabledReason: disabledReason(instance: instance, contentType: contentType)
                )
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        removeSection(section)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                    .tint(.red)
                }
                #endif
                .contextMenu {
                    Button(role: .destructive) {
                        removeSection(section)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                }
            }
        case .mediaSource(let sourceID):
            if let source = appEnvironment?.mediaSourcesManager.sources.first(where: { $0.id == sourceID }) {
                let isDisabled = !source.isEnabled
                
                HomeItemRow(
                    icon: source.type.systemImage,
                    title: "\(source.name) (\(source.type.displayName))",
                    isVisible: sectionBinding(for: section),
                    isDisabled: isDisabled,
                    disabledReason: isDisabled ? String(localized: "home.settings.sourceDisabled") : nil
                )
                #if os(iOS)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        removeSection(section)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                    .tint(.red)
                }
                #endif
                .contextMenu {
                    Button(role: .destructive) {
                        removeSection(section)
                    } label: {
                        Label(String(localized: "home.settings.remove"), systemImage: "trash")
                    }
                }
            }
        default:
            HomeItemRow(
                icon: section.icon,
                title: section.localizedTitle,
                isVisible: sectionBinding(for: section)
            )
        }
    }
    
    @ViewBuilder
    private func availableShortcutRow(for card: HomeShortcutItem, instance: Instance) -> some View {
        if case .instanceContent(_, let contentType) = card {
            let isDisabled = !instance.isEnabled || (contentType == .feed && !isLoggedIn(instance))
            
            HStack {
                Image(systemName: contentType.icon)
                    .frame(width: 24)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                
                Text("\(instance.displayName) - \(contentType.localizedTitle)")
                    .foregroundStyle(isDisabled ? .tertiary : .primary)
                
                Spacer()
                
                Button {
                    addShortcut(card)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            #if !os(tvOS)
            .help(isDisabled ? (disabledReason(instance: instance, contentType: contentType) ?? "") : "")
            #endif
        }
    }
    
    @ViewBuilder
    private func availableSectionRow(for section: HomeSectionItem, instance: Instance) -> some View {
        if case .instanceContent(_, let contentType) = section {
            let isDisabled = !instance.isEnabled || (contentType == .feed && !isLoggedIn(instance))
            
            HStack {
                Image(systemName: contentType.icon)
                    .frame(width: 24)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                
                Text("\(instance.displayName) - \(contentType.localizedTitle)")
                    .foregroundStyle(isDisabled ? .tertiary : .primary)
                
                Spacer()
                
                Button {
                    addSection(section)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            #if !os(tvOS)
            .help(isDisabled ? (disabledReason(instance: instance, contentType: contentType) ?? "") : "")
            #endif
        }
    }

    private func instanceFromID(_ id: UUID) -> Instance? {
        appEnvironment?.instancesManager.instances.first(where: { $0.id == id })
    }

    private func isLoggedIn(_ instance: Instance) -> Bool {
        guard instance.supportsFeed else { return false }
        return appEnvironment?.credentialsManager(for: instance)?.isLoggedIn(for: instance) ?? false
    }

    private func disabledReason(instance: Instance, contentType: InstanceContentType) -> String? {
        if !instance.isEnabled {
            return String(localized: "home.settings.instanceDisabled")
        }
        if contentType == .feed && !isLoggedIn(instance) {
            return String(localized: "home.settings.feedRequiresLogin")
        }
        return nil
    }

    @ViewBuilder
    private func availableMediaSourceShortcutRow(for card: HomeShortcutItem, source: MediaSource) -> some View {
        if case .mediaSource = card {
            let isDisabled = !source.isEnabled
            
            HStack {
                Image(systemName: source.type.systemImage)
                    .frame(width: 24)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                
                Text("\(source.name) (\(source.type.displayName))")
                    .foregroundStyle(isDisabled ? .tertiary : .primary)
                
                Spacer()
                
                Button {
                    addShortcut(card)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            #if !os(tvOS)
            .help(isDisabled ? String(localized: "home.settings.sourceDisabled") : "")
            #endif
        }
    }
    
    @ViewBuilder
    private func availableMediaSourceSectionRow(for section: HomeSectionItem, source: MediaSource) -> some View {
        if case .mediaSource = section {
            let isDisabled = !source.isEnabled
            
            HStack {
                Image(systemName: source.type.systemImage)
                    .frame(width: 24)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                
                Text("\(source.name) (\(source.type.displayName))")
                    .foregroundStyle(isDisabled ? .tertiary : .primary)
                
                Spacer()
                
                Button {
                    addSection(section)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
            }
            #if !os(tvOS)
            .help(isDisabled ? String(localized: "home.settings.sourceDisabled") : "")
            #endif
        }
    }
}

// MARK: - Home Item Row

#if os(tvOS)
private struct TVHomeItemRow: View {
    let icon: String
    let title: String
    @Binding var isVisible: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    var canDelete: Bool = false
    var onDelete: (() -> Void)? = nil
    
    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Move buttons - compact style
            VStack(spacing: 4) {
                Button {
                    onMoveUp()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                        .foregroundStyle(canMoveUp ? .primary : .tertiary)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(TVCompactButtonStyle())
                .disabled(!canMoveUp)

                Button {
                    onMoveDown()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(canMoveDown ? .primary : .tertiary)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(TVCompactButtonStyle())
                .disabled(!canMoveDown)
            }

            // Main content - toggle visibility
            Button {
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
                        .foregroundColor(isVisible ? .green : .secondary)
                        .font(.title3)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TVFormRowButtonStyle())
            
            // Delete button (only for instance content)
            if canDelete {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(TVCompactButtonStyle())
                .alert(String(localized: "home.removeConfirmation.title"), isPresented: $showingDeleteConfirmation) {
                    Button(String(localized: "common.cancel"), role: .cancel) { }
                    Button("common.remove", role: .destructive) {
                        onDelete?()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Compact button style for small controls like up/down arrows
private struct TVCompactButtonStyle: ButtonStyle {
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

private struct HomeItemRow: View {
    let icon: String
    let title: String
    @Binding var isVisible: Bool
    var isDisabled: Bool = false
    var disabledReason: String? = nil

    var body: some View {
        #if os(tvOS)
        Button {
            if !isDisabled {
                isVisible.toggle()
            }
        } label: {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(isDisabled ? .tertiary : .secondary)
                Text(title)
                    .foregroundStyle(isDisabled ? .tertiary : .primary)
                Spacer()
                Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDisabled ? .secondary.opacity(0.5) : (isVisible ? .green : .secondary))
                    .font(.title3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TVFormRowButtonStyle())
        .disabled(isDisabled)
        #else
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(isDisabled ? .tertiary : .secondary)
            Text(title)
                .foregroundStyle(isDisabled ? .tertiary : .primary)
            Spacer()
            Toggle("", isOn: $isVisible)
                .labelsHidden()
                .disabled(isDisabled)
        }
        .help(disabledReason ?? "")
        #endif
    }
}

// MARK: - Preview

#Preview {
    HomeSettingsView()
        .appEnvironment(.preview)
}
