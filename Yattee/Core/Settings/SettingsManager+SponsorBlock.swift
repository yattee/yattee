//
//  SettingsManager+SponsorBlock.swift
//  Yattee
//
//  SponsorBlock integration settings.
//

import Foundation

extension SettingsManager {
    // MARK: - SponsorBlock Settings

    /// The SponsorBlock API URL. Defaults to the official instance.
    static let defaultSponsorBlockAPIURL = "https://sponsor.ajay.app"

    var sponsorBlockEnabled: Bool {
        get {
            if let cached = _sponsorBlockEnabled { return cached }
            return bool(for: .sponsorBlockEnabled, default: true)
        }
        set {
            _sponsorBlockEnabled = newValue
            set(newValue, for: .sponsorBlockEnabled)
        }
    }

    var sponsorBlockCategories: Set<SponsorBlockCategory> {
        get {
            if let cached = _sponsorBlockCategories { return cached }
            guard let data = data(for: .sponsorBlockCategories),
                  let categories = try? JSONDecoder().decode(Set<SponsorBlockCategory>.self, from: data) else {
                return SponsorBlockCategory.defaultEnabled
            }
            return categories
        }
        set {
            _sponsorBlockCategories = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                set(data, for: .sponsorBlockCategories)
            }
        }
    }

    var sponsorBlockAPIURL: String {
        get {
            if let cached = _sponsorBlockAPIURL { return cached }
            return string(for: .sponsorBlockAPIURL) ?? Self.defaultSponsorBlockAPIURL
        }
        set {
            _sponsorBlockAPIURL = newValue
            set(newValue, for: .sponsorBlockAPIURL)
        }
    }
}
