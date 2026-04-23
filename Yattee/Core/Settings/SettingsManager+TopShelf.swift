//
//  SettingsManager+TopShelf.swift
//  Yattee
//
//  tvOS Top Shelf settings.
//

import Foundation

extension SettingsManager {
    /// Ordered list of sections visible in the tvOS Top Shelf.
    /// Inclusion means the section is shown; absence hides it.
    var topShelfSections: [TopShelfSection] {
        get {
            if let cached = _topShelfSections { return cached }
            guard let data = data(for: .topShelfSections),
                  let saved = try? JSONDecoder().decode([TopShelfSection].self, from: data) else {
                return TopShelfSection.defaultOrder
            }
            return saved
        }
        set {
            _topShelfSections = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .topShelfSections)
            }
            let tsKey = modifiedAtKey(for: .topShelfSections)
            let now = Date().timeIntervalSince1970
            localDefaults.set(now, forKey: tsKey)
            if iCloudSyncEnabled && syncSettings && !isInitialSyncPending {
                ubiquitousStore.set(now, forKey: tsKey)
            }
            mirrorEnabledSectionsToAppGroup(newValue)
        }
    }

    /// Mirrors the enabled-sections list to the App Group UserDefaults suite
    /// so the tvOS Top Shelf extension can read the user's selection.
    func mirrorEnabledSectionsToAppGroup(_ sections: [TopShelfSection]) {
        let rawValues = sections.map(\.rawValue)
        AppGroup.defaults.set(rawValues, forKey: AppGroup.enabledSectionsKey)
    }
}
