//
//  SettingsManager+Home.swift
//  Yattee
//
//  Home, tab bar, and sidebar settings and management functions.
//

import Foundation

extension SettingsManager {
    // MARK: - Home Shortcut Settings

    /// Ordered list of home shortcuts. Default order is playlists, history, downloads.
    var homeShortcutOrder: [HomeShortcutItem] {
        get {
            if let cached = _homeShortcutOrder { return cached }
            guard let data = data(for: .homeShortcutOrder),
                  let savedOrder = try? JSONDecoder().decode([HomeShortcutItem].self, from: data) else {
                return HomeShortcutItem.defaultOrder
            }

            // Merge saved order with default order to include any new items
            var mergedOrder = savedOrder
            for item in HomeShortcutItem.defaultOrder {
                if !mergedOrder.contains(item) {
                    // Insert new items at their default position
                    if let defaultIndex = HomeShortcutItem.defaultOrder.firstIndex(of: item) {
                        let insertIndex = min(defaultIndex, mergedOrder.count)
                        mergedOrder.insert(item, at: insertIndex)
                    } else {
                        mergedOrder.append(item)
                    }
                }
            }
            return mergedOrder
        }
        set {
            _homeShortcutOrder = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .homeShortcutOrder)
            }
            let tsKey = modifiedAtKey(for: .homeShortcutOrder)
            let now = Date().timeIntervalSince1970
            localDefaults.set(now, forKey: tsKey)
            if iCloudSyncEnabled && syncSettings && !isInitialSyncPending {
                ubiquitousStore.set(now, forKey: tsKey)
            }
        }
    }

    /// Visibility map for home shortcuts. Default is all visible.
    var homeShortcutVisibility: [HomeShortcutItem: Bool] {
        get {
            if let cached = _homeShortcutVisibility { return cached }
            guard let data = data(for: .homeShortcutVisibility),
                  let savedVisibility = try? JSONDecoder().decode([HomeShortcutItem: Bool].self, from: data) else {
                return HomeShortcutItem.defaultVisibility
            }

            // Merge saved visibility with defaults for any new items
            var mergedVisibility = savedVisibility
            for (item, defaultValue) in HomeShortcutItem.defaultVisibility {
                if mergedVisibility[item] == nil {
                    mergedVisibility[item] = defaultValue
                }
            }
            return mergedVisibility
        }
        set {
            _homeShortcutVisibility = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .homeShortcutVisibility)
            }
            let tsKey = modifiedAtKey(for: .homeShortcutVisibility)
            let now = Date().timeIntervalSince1970
            localDefaults.set(now, forKey: tsKey)
            if iCloudSyncEnabled && syncSettings && !isInitialSyncPending {
                ubiquitousStore.set(now, forKey: tsKey)
            }
        }
    }

    /// Layout mode for home shortcuts (list or cards). Default is cards.
    var homeShortcutLayout: HomeShortcutLayout {
        get {
            if let cached = _homeShortcutLayout { return cached }
            guard let rawValue = string(for: .homeShortcutLayout) else {
                return .cards
            }
            return HomeShortcutLayout(rawValue: rawValue) ?? .cards
        }
        set {
            _homeShortcutLayout = newValue
            set(newValue.rawValue, for: .homeShortcutLayout)
        }
    }

    /// Layout mode for home sections (list or grid). Default is list on iOS/macOS, grid on tvOS.
    var homeSectionLayout: HomeSectionLayout {
        get {
            if let cached = _homeSectionLayout { return cached }
            guard let rawValue = string(for: .homeSectionLayout) else {
                return HomeSectionLayout.platformDefault
            }
            return HomeSectionLayout(rawValue: rawValue) ?? HomeSectionLayout.platformDefault
        }
        set {
            _homeSectionLayout = newValue
            set(newValue.rawValue, for: .homeSectionLayout)
        }
    }

    // MARK: - Home Section Settings

    /// Ordered list of home sections. Default order is bookmarks, history, downloads.
    var homeSectionOrder: [HomeSectionItem] {
        get {
            if let cached = _homeSectionOrder { return cached }
            guard let data = data(for: .homeSectionOrder),
                  let savedOrder = try? JSONDecoder().decode([HomeSectionItem].self, from: data) else {
                return HomeSectionItem.defaultOrder
            }

            // Merge saved order with default order to include any new items
            var mergedOrder = savedOrder
            for item in HomeSectionItem.defaultOrder {
                if !mergedOrder.contains(item) {
                    // Insert new items at their default position
                    if let defaultIndex = HomeSectionItem.defaultOrder.firstIndex(of: item) {
                        let insertIndex = min(defaultIndex, mergedOrder.count)
                        mergedOrder.insert(item, at: insertIndex)
                    } else {
                        mergedOrder.append(item)
                    }
                }
            }
            return mergedOrder
        }
        set {
            _homeSectionOrder = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .homeSectionOrder)
            }
            let tsKey = modifiedAtKey(for: .homeSectionOrder)
            let now = Date().timeIntervalSince1970
            localDefaults.set(now, forKey: tsKey)
            if iCloudSyncEnabled && syncSettings && !isInitialSyncPending {
                ubiquitousStore.set(now, forKey: tsKey)
            }
        }
    }

    /// Visibility map for home sections. Default is bookmarks and history visible, downloads hidden.
    var homeSectionVisibility: [HomeSectionItem: Bool] {
        get {
            if let cached = _homeSectionVisibility { return cached }
            guard let data = data(for: .homeSectionVisibility),
                  let savedVisibility = try? JSONDecoder().decode([HomeSectionItem: Bool].self, from: data) else {
                return HomeSectionItem.defaultVisibility
            }

            // Merge saved visibility with defaults for any new items
            var mergedVisibility = savedVisibility
            for (item, defaultValue) in HomeSectionItem.defaultVisibility {
                if mergedVisibility[item] == nil {
                    mergedVisibility[item] = defaultValue
                }
            }
            return mergedVisibility
        }
        set {
            _homeSectionVisibility = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .homeSectionVisibility)
            }
            let tsKey = modifiedAtKey(for: .homeSectionVisibility)
            let now = Date().timeIntervalSince1970
            localDefaults.set(now, forKey: tsKey)
            if iCloudSyncEnabled && syncSettings && !isInitialSyncPending {
                ubiquitousStore.set(now, forKey: tsKey)
            }
        }
    }

    /// Number of items to show in each home section. Default is 5.
    static let defaultHomeSectionItemsLimit = 5

    var homeSectionItemsLimit: Int {
        get {
            if let cached = _homeSectionItemsLimit { return cached }
            return integer(for: .homeSectionItemsLimit, default: Self.defaultHomeSectionItemsLimit)
        }
        set {
            _homeSectionItemsLimit = newValue
            set(newValue, for: .homeSectionItemsLimit)
        }
    }

    /// Returns visible shortcuts in their configured order.
    func visibleShortcuts() -> [HomeShortcutItem] {
        let visibility = homeShortcutVisibility
        return homeShortcutOrder.filter { visibility[$0] ?? true }
    }

    /// Returns visible sections in their configured order.
    func visibleSections() -> [HomeSectionItem] {
        let visibility = homeSectionVisibility
        return homeSectionOrder.filter { visibility[$0] ?? false }
    }

    // MARK: - Home Instance Items Management

    /// Adds an instance content item to Home as a card or section.
    func addToHome(instanceID: UUID, contentType: InstanceContentType, asCard: Bool) {
        if asCard {
            // Add to cards
            let newCard = HomeShortcutItem.instanceContent(instanceID: instanceID, contentType: contentType)
            var order = homeShortcutOrder
            if !order.contains(where: { $0.id == newCard.id }) {
                order.append(newCard)
                homeShortcutOrder = order
            }
            // Set visible by default
            var visibility = homeShortcutVisibility
            visibility[newCard] = true
            homeShortcutVisibility = visibility
        } else {
            // Add to sections
            let newSection = HomeSectionItem.instanceContent(instanceID: instanceID, contentType: contentType)
            var order = homeSectionOrder
            if !order.contains(where: { $0.id == newSection.id }) {
                order.append(newSection)
                homeSectionOrder = order
            }
            // Set visible by default
            var visibility = homeSectionVisibility
            visibility[newSection] = true
            homeSectionVisibility = visibility
        }
    }

    /// Removes an instance content item from Home (both cards and sections).
    func removeFromHome(instanceID: UUID, contentType: InstanceContentType) {
        // Remove from cards
        var cardOrder = homeShortcutOrder
        cardOrder.removeAll { item in
            if case .instanceContent(let id, let type) = item {
                return id == instanceID && type == contentType
            }
            return false
        }
        homeShortcutOrder = cardOrder

        // Remove from card visibility
        var cardVis = homeShortcutVisibility
        cardVis.removeValue(forKey: .instanceContent(instanceID: instanceID, contentType: contentType))
        homeShortcutVisibility = cardVis

        // Remove from sections
        var sectionOrder = homeSectionOrder
        sectionOrder.removeAll { item in
            if case .instanceContent(let id, let type) = item {
                return id == instanceID && type == contentType
            }
            return false
        }
        homeSectionOrder = sectionOrder

        // Remove from section visibility
        var sectionVis = homeSectionVisibility
        sectionVis.removeValue(forKey: .instanceContent(instanceID: instanceID, contentType: contentType))
        homeSectionVisibility = sectionVis
    }

    /// Checks if an instance content item is in Home (either as card or section).
    func isInHome(instanceID: UUID, contentType: InstanceContentType) -> (inCards: Bool, inSections: Bool) {
        let inCards = homeShortcutOrder.contains { item in
            if case .instanceContent(let id, let type) = item {
                return id == instanceID && type == contentType
            }
            return false
        }

        let inSections = homeSectionOrder.contains { item in
            if case .instanceContent(let id, let type) = item {
                return id == instanceID && type == contentType
            }
            return false
        }

        return (inCards, inSections)
    }

    /// Removes all Home items for instances that no longer exist.
    func cleanupOrphanedHomeInstanceItems(validInstanceIDs: Set<UUID>) {
        // Collect orphaned instance IDs for cache cleanup
        var orphanedInstanceIDs = Set<UUID>()

        // Clean up cards - only write if items were actually removed
        var cardOrder = homeShortcutOrder
        let originalCardCount = cardOrder.count
        cardOrder.removeAll { item in
            if case .instanceContent(let instanceID, _) = item {
                if !validInstanceIDs.contains(instanceID) {
                    orphanedInstanceIDs.insert(instanceID)
                    return true
                }
            }
            return false
        }
        if cardOrder.count != originalCardCount {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeInstanceItems: removed \(originalCardCount - cardOrder.count) orphaned cards")
            homeShortcutOrder = cardOrder
        }

        // Clean up card visibility - only write if orphaned keys found
        var cardVis = homeShortcutVisibility
        let orphanedCardKeys = cardVis.keys.filter { item in
            if case .instanceContent(let instanceID, _) = item {
                if !validInstanceIDs.contains(instanceID) {
                    orphanedInstanceIDs.insert(instanceID)
                    return true
                }
            }
            return false
        }
        if !orphanedCardKeys.isEmpty {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeInstanceItems: removed \(orphanedCardKeys.count) orphaned card visibility entries")
            for key in orphanedCardKeys {
                cardVis.removeValue(forKey: key)
            }
            homeShortcutVisibility = cardVis
        }

        // Clean up sections - only write if items were actually removed
        var sectionOrder = homeSectionOrder
        let originalSectionCount = sectionOrder.count
        sectionOrder.removeAll { item in
            if case .instanceContent(let instanceID, _) = item {
                if !validInstanceIDs.contains(instanceID) {
                    orphanedInstanceIDs.insert(instanceID)
                    return true
                }
            }
            return false
        }
        if sectionOrder.count != originalSectionCount {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeInstanceItems: removed \(originalSectionCount - sectionOrder.count) orphaned sections")
            homeSectionOrder = sectionOrder
        }

        // Clean up section visibility - only write if orphaned keys found
        var sectionVis = homeSectionVisibility
        let orphanedSectionKeys = sectionVis.keys.filter { item in
            if case .instanceContent(let instanceID, _) = item {
                if !validInstanceIDs.contains(instanceID) {
                    orphanedInstanceIDs.insert(instanceID)
                    return true
                }
            }
            return false
        }
        if !orphanedSectionKeys.isEmpty {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeInstanceItems: removed \(orphanedSectionKeys.count) orphaned section visibility entries")
            for key in orphanedSectionKeys {
                sectionVis.removeValue(forKey: key)
            }
            homeSectionVisibility = sectionVis
        }

        // Clear cache for orphaned instances
        for instanceID in orphanedInstanceIDs {
            HomeInstanceCache.shared.clearAllForInstance(instanceID)
        }

        if orphanedInstanceIDs.isEmpty {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeInstanceItems: no orphans found, skipped all writes")
        }
    }

    /// Returns available content types for an instance.
    /// Feed is always included for instances that support it, even if user is not logged in.
    /// The UI will disable the toggle when not logged in.
    func availableContentTypes(for instance: Instance) -> [InstanceContentType] {
        var types: [InstanceContentType] = [.popular, .trending]

        // Always add Feed for instances that support it (Invidious)
        // Toggle will be disabled in UI if not logged in
        if instance.supportsFeed {
            types.insert(.feed, at: 0)  // Feed first
        }

        return types
    }

    /// Returns all available card items for an instance that are NOT already added.
    func availableShortcuts(for instance: Instance) -> [HomeShortcutItem] {
        let contentTypes = availableContentTypes(for: instance)
        let existingCards = Set(homeShortcutOrder.map { $0.id })

        return contentTypes.compactMap { contentType in
            let card = HomeShortcutItem.instanceContent(instanceID: instance.id, contentType: contentType)
            return existingCards.contains(card.id) ? nil : card
        }
    }

    /// Returns all available section items for an instance that are NOT already added.
    func availableSections(for instance: Instance) -> [HomeSectionItem] {
        let contentTypes = availableContentTypes(for: instance)
        let existingSections = Set(homeSectionOrder.map { $0.id })

        return contentTypes.compactMap { contentType in
            let section = HomeSectionItem.instanceContent(instanceID: instance.id, contentType: contentType)
            return existingSections.contains(section.id) ? nil : section
        }
    }

    /// Returns all available cards across all instances, grouped by instance.
    func allAvailableShortcuts(instances: [Instance]) -> [(instance: Instance, cards: [HomeShortcutItem])] {
        instances.compactMap { instance in
            let cards = availableShortcuts(for: instance)
            return cards.isEmpty ? nil : (instance, cards)
        }
    }

    /// Returns all available sections across all instances, grouped by instance.
    func allAvailableSections(instances: [Instance]) -> [(instance: Instance, sections: [HomeSectionItem])] {
        instances.compactMap { instance in
            let sections = availableSections(for: instance)
            return sections.isEmpty ? nil : (instance, sections)
        }
    }

    // MARK: - Home Media Source Items Management

    /// Adds a media source to Home as a card or section.
    func addToHome(sourceID: UUID, asCard: Bool) {
        if asCard {
            // Add to cards
            let newCard = HomeShortcutItem.mediaSource(sourceID: sourceID)
            var order = homeShortcutOrder
            if !order.contains(where: { $0.id == newCard.id }) {
                order.append(newCard)
                homeShortcutOrder = order
            }
            // Set visible by default
            var visibility = homeShortcutVisibility
            visibility[newCard] = true
            homeShortcutVisibility = visibility
        } else {
            // Add to sections
            let newSection = HomeSectionItem.mediaSource(sourceID: sourceID)
            var order = homeSectionOrder
            if !order.contains(where: { $0.id == newSection.id }) {
                order.append(newSection)
                homeSectionOrder = order
            }
            // Set visible by default
            var visibility = homeSectionVisibility
            visibility[newSection] = true
            homeSectionVisibility = visibility
        }
    }

    /// Removes a media source from Home (both cards and sections).
    func removeFromHome(sourceID: UUID) {
        // Remove from cards
        var cardOrder = homeShortcutOrder
        cardOrder.removeAll { item in
            if case .mediaSource(let id) = item {
                return id == sourceID
            }
            return false
        }
        homeShortcutOrder = cardOrder

        // Remove from card visibility
        var cardVis = homeShortcutVisibility
        cardVis.removeValue(forKey: .mediaSource(sourceID: sourceID))
        homeShortcutVisibility = cardVis

        // Remove from sections
        var sectionOrder = homeSectionOrder
        sectionOrder.removeAll { item in
            if case .mediaSource(let id) = item {
                return id == sourceID
            }
            return false
        }
        homeSectionOrder = sectionOrder

        // Remove from section visibility
        var sectionVis = homeSectionVisibility
        sectionVis.removeValue(forKey: .mediaSource(sourceID: sourceID))
        homeSectionVisibility = sectionVis
    }

    /// Checks if a media source is in Home (either as card or section).
    func isInHome(sourceID: UUID) -> (inCards: Bool, inSections: Bool) {
        let inCards = homeShortcutOrder.contains { item in
            if case .mediaSource(let id) = item {
                return id == sourceID
            }
            return false
        }

        let inSections = homeSectionOrder.contains { item in
            if case .mediaSource(let id) = item {
                return id == sourceID
            }
            return false
        }

        return (inCards, inSections)
    }

    /// Returns all available card items for a media source that are NOT already added.
    func availableShortcuts(for source: MediaSource) -> [HomeShortcutItem] {
        let card = HomeShortcutItem.mediaSource(sourceID: source.id)
        let existingCards = Set(homeShortcutOrder.map { $0.id })
        return existingCards.contains(card.id) ? [] : [card]
    }

    /// Returns all available section items for a media source that are NOT already added.
    func availableSections(for source: MediaSource) -> [HomeSectionItem] {
        let section = HomeSectionItem.mediaSource(sourceID: source.id)
        let existingSections = Set(homeSectionOrder.map { $0.id })
        return existingSections.contains(section.id) ? [] : [section]
    }

    /// Returns all available cards across all media sources, grouped by source.
    func allAvailableMediaSourceShortcuts(sources: [MediaSource]) -> [(source: MediaSource, cards: [HomeShortcutItem])] {
        sources.compactMap { source in
            let cards = availableShortcuts(for: source)
            return cards.isEmpty ? nil : (source, cards)
        }
    }

    /// Returns all available sections across all media sources, grouped by source.
    func allAvailableMediaSourceSections(sources: [MediaSource]) -> [(source: MediaSource, sections: [HomeSectionItem])] {
        sources.compactMap { source in
            let sections = availableSections(for: source)
            return sections.isEmpty ? nil : (source, sections)
        }
    }

    /// Removes all Home items for media sources that no longer exist.
    func cleanupOrphanedHomeMediaSourceItems(validSourceIDs: Set<UUID>) {
        var hadOrphans = false

        // Clean up cards - only write if items were actually removed
        var cardOrder = homeShortcutOrder
        let originalCardCount = cardOrder.count
        cardOrder.removeAll { item in
            if case .mediaSource(let sourceID) = item {
                return !validSourceIDs.contains(sourceID)
            }
            return false
        }
        if cardOrder.count != originalCardCount {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeMediaSourceItems: removed \(originalCardCount - cardOrder.count) orphaned cards")
            homeShortcutOrder = cardOrder
            hadOrphans = true
        }

        // Clean up card visibility - only write if orphaned keys found
        var cardVis = homeShortcutVisibility
        let orphanedCardKeys = cardVis.keys.filter { item in
            if case .mediaSource(let sourceID) = item {
                return !validSourceIDs.contains(sourceID)
            }
            return false
        }
        if !orphanedCardKeys.isEmpty {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeMediaSourceItems: removed \(orphanedCardKeys.count) orphaned card visibility entries")
            for key in orphanedCardKeys {
                cardVis.removeValue(forKey: key)
            }
            homeShortcutVisibility = cardVis
            hadOrphans = true
        }

        // Clean up sections - only write if items were actually removed
        var sectionOrder = homeSectionOrder
        let originalSectionCount = sectionOrder.count
        sectionOrder.removeAll { item in
            if case .mediaSource(let sourceID) = item {
                return !validSourceIDs.contains(sourceID)
            }
            return false
        }
        if sectionOrder.count != originalSectionCount {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeMediaSourceItems: removed \(originalSectionCount - sectionOrder.count) orphaned sections")
            homeSectionOrder = sectionOrder
            hadOrphans = true
        }

        // Clean up section visibility - only write if orphaned keys found
        var sectionVis = homeSectionVisibility
        let orphanedSectionKeys = sectionVis.keys.filter { item in
            if case .mediaSource(let sourceID) = item {
                return !validSourceIDs.contains(sourceID)
            }
            return false
        }
        if !orphanedSectionKeys.isEmpty {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeMediaSourceItems: removed \(orphanedSectionKeys.count) orphaned section visibility entries")
            for key in orphanedSectionKeys {
                sectionVis.removeValue(forKey: key)
            }
            homeSectionVisibility = sectionVis
            hadOrphans = true
        }

        if !hadOrphans {
            LoggingService.shared.logCloudKit("cleanupOrphanedHomeMediaSourceItems: no orphans found, skipped all writes")
        }
    }

    // MARK: - Tab Bar Settings (Compact Size Class)

    /// Ordered list of tab bar items. Default order is subscriptions first, then others.
    var tabBarItemOrder: [TabBarItem] {
        get {
            if let cached = _tabBarItemOrder { return cached }
            guard let data = data(for: .tabBarItemOrder),
                  let savedOrder = try? JSONDecoder().decode([TabBarItem].self, from: data) else {
                return TabBarItem.defaultOrder
            }

            // Merge saved order with default order to include any new items
            var mergedOrder = savedOrder
            for item in TabBarItem.defaultOrder {
                if !mergedOrder.contains(item) {
                    if let defaultIndex = TabBarItem.defaultOrder.firstIndex(of: item) {
                        let insertIndex = min(defaultIndex, mergedOrder.count)
                        mergedOrder.insert(item, at: insertIndex)
                    } else {
                        mergedOrder.append(item)
                    }
                }
            }
            return mergedOrder
        }
        set {
            _tabBarItemOrder = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .tabBarItemOrder)
            }
        }
    }

    /// Visibility map for tab bar items. Default is only subscriptions visible.
    var tabBarItemVisibility: [TabBarItem: Bool] {
        get {
            if let cached = _tabBarItemVisibility { return cached }
            guard let data = data(for: .tabBarItemVisibility),
                  let savedVisibility = try? JSONDecoder().decode([TabBarItem: Bool].self, from: data) else {
                return TabBarItem.defaultVisibility
            }

            // Merge saved visibility with defaults for any new items
            var mergedVisibility = savedVisibility
            for (item, defaultValue) in TabBarItem.defaultVisibility {
                if mergedVisibility[item] == nil {
                    mergedVisibility[item] = defaultValue
                }
            }
            return mergedVisibility
        }
        set {
            _tabBarItemVisibility = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .tabBarItemVisibility)
            }
        }
    }

    /// Returns visible tab bar items in their configured order.
    func visibleTabBarItems() -> [TabBarItem] {
        let visibility = tabBarItemVisibility
        return tabBarItemOrder
            .filter { visibility[$0] ?? false }
    }

    // MARK: - Sidebar Main Navigation Settings

    /// Ordered list of sidebar main navigation items.
    var sidebarMainItemOrder: [SidebarMainItem] {
        get {
            if let cached = _sidebarMainItemOrder { return cached }
            guard let data = data(for: .sidebarMainItemOrder),
                  let savedOrder = try? JSONDecoder().decode([SidebarMainItem].self, from: data) else {
                return SidebarMainItem.defaultOrder
            }

            // Merge saved order with default order to include any new items
            var mergedOrder = savedOrder
            for item in SidebarMainItem.defaultOrder {
                if !mergedOrder.contains(item) {
                    if let defaultIndex = SidebarMainItem.defaultOrder.firstIndex(of: item) {
                        let insertIndex = min(defaultIndex, mergedOrder.count)
                        mergedOrder.insert(item, at: insertIndex)
                    } else {
                        mergedOrder.append(item)
                    }
                }
            }
            return mergedOrder
        }
        set {
            _sidebarMainItemOrder = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .sidebarMainItemOrder)
            }
        }
    }

    /// Visibility map for sidebar main navigation items.
    var sidebarMainItemVisibility: [SidebarMainItem: Bool] {
        get {
            if let cached = _sidebarMainItemVisibility { return cached }
            guard let data = data(for: .sidebarMainItemVisibility),
                  let savedVisibility = try? JSONDecoder().decode([SidebarMainItem: Bool].self, from: data) else {
                return SidebarMainItem.defaultVisibility
            }

            // Merge saved visibility with defaults for any new items
            var mergedVisibility = savedVisibility
            for (item, defaultValue) in SidebarMainItem.defaultVisibility {
                if mergedVisibility[item] == nil {
                    mergedVisibility[item] = defaultValue
                }
            }
            return mergedVisibility
        }
        set {
            _sidebarMainItemVisibility = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .sidebarMainItemVisibility)
            }
        }
    }

    /// Returns visible sidebar main items in their configured order.
    func visibleSidebarMainItems() -> [SidebarMainItem] {
        let visibility = sidebarMainItemVisibility
        return sidebarMainItemOrder
            .filter { $0.isAvailableOnCurrentPlatform }
            .filter { $0.isRequired || (visibility[$0] ?? true) }
    }

    // MARK: - Sidebar Sources Settings

    /// Whether to show the Sources section in the sidebar. Default is true.
    var sidebarSourcesEnabled: Bool {
        get {
            if let cached = _sidebarSourcesEnabled { return cached }
            return bool(for: .sidebarSourcesEnabled, default: true)
        }
        set {
            _sidebarSourcesEnabled = newValue
            set(newValue, for: .sidebarSourcesEnabled)
        }
    }

    /// How sources are sorted in the sidebar. Default is name.
    var sidebarSourceSort: SidebarSourceSort {
        get {
            if let cached = _sidebarSourceSort { return cached }
            guard let rawValue = string(for: .sidebarSourceSort) else {
                return .name
            }
            return SidebarSourceSort(rawValue: rawValue) ?? .name
        }
        set {
            _sidebarSourceSort = newValue
            set(newValue.rawValue, for: .sidebarSourceSort)
        }
    }

    /// Whether to limit the number of sources in the sidebar. Default is false (shows all).
    var sidebarSourcesLimitEnabled: Bool {
        get {
            if let cached = _sidebarSourcesLimitEnabled { return cached }
            return bool(for: .sidebarSourcesLimitEnabled, default: false)
        }
        set {
            _sidebarSourcesLimitEnabled = newValue
            set(newValue, for: .sidebarSourcesLimitEnabled)
        }
    }

    /// Maximum number of sources to show in the sidebar. Default is 10.
    static let defaultSidebarMaxSources = 10

    var sidebarMaxSources: Int {
        get {
            if let cached = _sidebarMaxSources { return cached }
            return integer(for: .sidebarMaxSources, default: Self.defaultSidebarMaxSources)
        }
        set {
            _sidebarMaxSources = newValue
            set(newValue, for: .sidebarMaxSources)
        }
    }

    // MARK: - Sidebar Channels Settings

    /// Whether to show the Channels section in the sidebar. Default is true.
    var sidebarChannelsEnabled: Bool {
        get {
            if let cached = _sidebarChannelsEnabled { return cached }
            return bool(for: .sidebarChannelsEnabled, default: true)
        }
        set {
            _sidebarChannelsEnabled = newValue
            set(newValue, for: .sidebarChannelsEnabled)
        }
    }

    /// Maximum number of channels to show in the sidebar. Default is 10.
    static let defaultSidebarMaxChannels = 10

    var sidebarMaxChannels: Int {
        get {
            if let cached = _sidebarMaxChannels { return cached }
            return integer(for: .sidebarMaxChannels, default: Self.defaultSidebarMaxChannels)
        }
        set {
            _sidebarMaxChannels = newValue
            set(newValue, for: .sidebarMaxChannels)
        }
    }

    /// How channels are sorted in the sidebar. Default is lastUploaded.
    var sidebarChannelSort: SidebarChannelSort {
        get {
            if let cached = _sidebarChannelSort { return cached }
            guard let rawValue = string(for: .sidebarChannelSort) else {
                return .lastUploaded
            }
            return SidebarChannelSort(rawValue: rawValue) ?? .lastUploaded
        }
        set {
            _sidebarChannelSort = newValue
            set(newValue.rawValue, for: .sidebarChannelSort)
        }
    }

    /// Whether to limit the number of channels in the sidebar. Default is true.
    var sidebarChannelsLimitEnabled: Bool {
        get {
            if let cached = _sidebarChannelsLimitEnabled { return cached }
            return bool(for: .sidebarChannelsLimitEnabled, default: true)
        }
        set {
            _sidebarChannelsLimitEnabled = newValue
            set(newValue, for: .sidebarChannelsLimitEnabled)
        }
    }

    /// Whether to show the Playlists section in the sidebar. Default is true.
    var sidebarPlaylistsEnabled: Bool {
        get {
            if let cached = _sidebarPlaylistsEnabled { return cached }
            return bool(for: .sidebarPlaylistsEnabled, default: true)
        }
        set {
            _sidebarPlaylistsEnabled = newValue
            set(newValue, for: .sidebarPlaylistsEnabled)
        }
    }

    /// Maximum number of playlists to show in the sidebar. Default is 10.
    static let defaultSidebarMaxPlaylists = 10

    var sidebarMaxPlaylists: Int {
        get {
            if let cached = _sidebarMaxPlaylists { return cached }
            return integer(for: .sidebarMaxPlaylists, default: Self.defaultSidebarMaxPlaylists)
        }
        set {
            _sidebarMaxPlaylists = newValue
            set(newValue, for: .sidebarMaxPlaylists)
        }
    }

    /// How playlists are sorted in the sidebar. Default is alphabetical.
    var sidebarPlaylistSort: SidebarPlaylistSort {
        get {
            if let cached = _sidebarPlaylistSort { return cached }
            guard let rawValue = string(for: .sidebarPlaylistSort) else {
                return .alphabetical
            }
            return SidebarPlaylistSort(rawValue: rawValue) ?? .alphabetical
        }
        set {
            _sidebarPlaylistSort = newValue
            set(newValue.rawValue, for: .sidebarPlaylistSort)
        }
    }

    /// Whether to limit the number of playlists in the sidebar. Default is false (shows all).
    var sidebarPlaylistsLimitEnabled: Bool {
        get {
            if let cached = _sidebarPlaylistsLimitEnabled { return cached }
            return bool(for: .sidebarPlaylistsLimitEnabled, default: false)
        }
        set {
            _sidebarPlaylistsLimitEnabled = newValue
            set(newValue, for: .sidebarPlaylistsLimitEnabled)
        }
    }

    // MARK: - Startup Tab Settings

    /// The startup tab for tab bar mode (compact/iPhone). Default is home.
    var tabBarStartupTab: SidebarMainItem {
        get {
            if let cached = _tabBarStartupTab { return cached }
            guard let rawValue = string(for: .tabBarStartupTab) else {
                return .home
            }
            return SidebarMainItem(rawValue: rawValue) ?? .home
        }
        set {
            _tabBarStartupTab = newValue
            set(newValue.rawValue, for: .tabBarStartupTab)
        }
    }

    /// The startup tab for sidebar mode (iPad/Mac/tvOS). Default is home.
    var sidebarStartupTab: SidebarMainItem {
        get {
            if let cached = _sidebarStartupTab { return cached }
            guard let rawValue = string(for: .sidebarStartupTab) else {
                return .home
            }
            return SidebarMainItem(rawValue: rawValue) ?? .home
        }
        set {
            _sidebarStartupTab = newValue
            set(newValue.rawValue, for: .sidebarStartupTab)
        }
    }

    /// Valid startup tabs for tab bar mode.
    /// Includes fixed tabs (Home, Search) plus all visible configurable tabs.
    func validStartupTabsForTabBar() -> [SidebarMainItem] {
        // Fixed tabs always available
        var tabs: [SidebarMainItem] = [.home, .search]

        // Add visible configurable tabs
        let visibility = tabBarItemVisibility
        for item in tabBarItemOrder where visibility[item] ?? false {
            if let mainItem = SidebarMainItem(tabBarItem: item) {
                tabs.append(mainItem)
            }
        }

        return tabs
    }

    /// Valid startup tabs for sidebar mode.
    /// Includes all visible main navigation items.
    func validStartupTabsForSidebar() -> [SidebarMainItem] {
        visibleSidebarMainItems()
    }

    /// Effective startup tab for tab bar mode.
    /// Returns the configured startup tab if valid, otherwise falls back to home.
    func effectiveStartupTabForTabBar() -> SidebarMainItem {
        let validTabs = validStartupTabsForTabBar()
        let configured = tabBarStartupTab
        return validTabs.contains(configured) ? configured : .home
    }

    /// Effective startup tab for sidebar mode.
    /// Returns the configured startup tab if valid, otherwise falls back to home.
    func effectiveStartupTabForSidebar() -> SidebarMainItem {
        let validTabs = validStartupTabsForSidebar()
        let configured = sidebarStartupTab
        return validTabs.contains(configured) ? configured : .home
    }
}
