import Foundation

/// Feature flags for enabling/disabling functionality across the app
enum FeatureFlags {
    /// Controls whether the "Hide Shorts" functionality is available
    /// Set to false when the API changes prevent reliable detection of short videos
    static let hideShortsEnabled = false
}
