//
//  TranslationContributorsLoader.swift
//  Yattee
//
//  Loads and aggregates translation contributors from bundled JSON.
//

import Foundation

enum TranslationContributorsLoader {
    /// Raw contributor entry from JSON
    private struct RawContributor: Decodable {
        let gravatarHash: String
        let username: String
        let fullName: String
        let changeCount: Int

        enum CodingKeys: String, CodingKey {
            case gravatarHash = "gravatar_hash"
            case username
            case fullName = "full_name"
            case changeCount = "change_count"
        }
    }

    /// Loads and aggregates contributors from the bundled weblate-credits.json file.
    /// - Returns: Array of contributors sorted by total contributions descending.
    static func load() -> [TranslationContributor] {
        guard let url = Bundle.main.url(forResource: "weblate-credits", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else {
            return []
        }

        return parse(data: data)
    }

    /// Contributors whose contributions should only count for specific languages.
    /// Other language contributions are administrative (adding files) not translations.
    /// Key is the gravatar hash of the email address.
    private static let languageOverrides: [String: Set<String>] = [
        // arek@arekf.net
        "2845e3b7997a9be63ce293942da82c37": ["Polish"]
    ]

    /// Parses JSON data and aggregates contributors by gravatar hash.
    /// - Parameter data: JSON data in the format `[{language: [contributors]}]`
    /// - Returns: Array of contributors sorted by total contributions descending.
    static func parse(data: Data) -> [TranslationContributor] {
        // JSON is array of objects, each with single key (language) -> array of contributors
        guard let languageEntries = try? JSONDecoder().decode([[String: [RawContributor]]].self, from: data) else {
            return []
        }

        // Aggregate by gravatar hash
        var aggregated: [String: (
            gravatarHash: String,
            username: String,
            fullName: String,
            languages: [String: Int]
        )] = [:]

        for languageEntry in languageEntries {
            for (language, contributors) in languageEntry {
                for contributor in contributors {
                    // Skip contributions for languages not in the override list for this contributor
                    if let allowedLanguages = languageOverrides[contributor.gravatarHash],
                       !allowedLanguages.contains(language) {
                        continue
                    }

                    if var existing = aggregated[contributor.gravatarHash] {
                        existing.languages[language, default: 0] += contributor.changeCount
                        aggregated[contributor.gravatarHash] = existing
                    } else {
                        aggregated[contributor.gravatarHash] = (
                            gravatarHash: contributor.gravatarHash,
                            username: contributor.username,
                            fullName: contributor.fullName,
                            languages: [language: contributor.changeCount]
                        )
                    }
                }
            }
        }

        return aggregated.values
            .map { entry in
                TranslationContributor(
                    gravatarHash: entry.gravatarHash,
                    username: entry.username,
                    fullName: entry.fullName,
                    languageContributions: entry.languages
                )
            }
            .sorted { $0.totalContributions > $1.totalContributions }
    }
}
