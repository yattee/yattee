//
//  TranslationContributor.swift
//  Yattee
//
//  Data model for Weblate translation contributor information.
//

import Foundation

/// An aggregated translation contributor from Weblate.
struct TranslationContributor: Identifiable, Sendable {
    let gravatarHash: String
    let username: String
    let fullName: String
    /// Per-language contribution counts
    let languageContributions: [String: Int]

    var id: String { gravatarHash }

    var totalContributions: Int {
        languageContributions.values.reduce(0, +)
    }

    var displayName: String {
        fullName.isEmpty ? username : fullName
    }

    var gravatarURL: URL? {
        URL(string: "https://www.gravatar.com/avatar/\(gravatarHash)?d=identicon&s=200")
    }

    /// Returns top languages with counts formatted as "Polish (530), German (355), ..."
    func languageSummary(maxLanguages: Int = 3) -> String {
        let sorted = languageContributions
            .sorted { $0.value > $1.value }
            .prefix(maxLanguages)
            .map { "\($0.key) (\($0.value))" }

        var result = sorted.joined(separator: ", ")
        if languageContributions.count > maxLanguages {
            result += ", ..."
        }
        return result
    }
}
