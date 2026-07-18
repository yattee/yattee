//
//  PeerTubeDirectoryRow.swift
//  Yattee
//
//  Row view for displaying a PeerTube instance from the public directory.
//

import SwiftUI

struct PeerTubeDirectoryRow: View {
    let instance: PeerTubeDirectoryInstance
    let isAlreadyAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name and host
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(instance.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Add button or added indicator
                if isAlreadyAdded {
                    Label(String(localized: "peertube.explore.added"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(CompactLabelStyle())
                } else {
                    Button(action: onAdd) {
                        Label(String(localized: "common.add"), systemImage: "plus.circle")
                            .labelStyle(CompactLabelStyle())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Description
            if let description = instance.shortDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Stats row
            HStack(spacing: 16) {
                // Country
                if let country = instance.country, !country.isEmpty {
                    if let emoji = flagEmoji(for: country) {
                        HStack(spacing: 4) {
                            Text(emoji)
                            Text(country)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Label(country, systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(CompactLabelStyle())
                    }
                }

                // Users
                Label("\(instance.totalUsers.formatted())", systemImage: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(CompactLabelStyle())

                // Videos
                Label("\(instance.totalVideos.formatted())", systemImage: "film")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(CompactLabelStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private func flagEmoji(for countryCode: String) -> String? {
        guard countryCode.count == 2 else { return nil }
        let base: UInt32 = 0x1F1E6 - UInt32(UnicodeScalar("A").value)
        var emoji = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            guard scalar.value >= UInt32(UnicodeScalar("A").value),
                  scalar.value <= UInt32(UnicodeScalar("Z").value),
                  let flagScalar = UnicodeScalar(base + scalar.value) else { return nil }
            emoji.append(Character(flagScalar))
        }
        return emoji
    }
}

// MARK: - Compact Label Style

private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        PeerTubeDirectoryRow(
            instance: PeerTubeDirectoryInstance(
                id: 1,
                host: "peertube.example.com",
                name: "Example PeerTube",
                shortDescription: "A community video platform for sharing creative content.",
                version: "5.0.0",
                signupAllowed: true,
                languages: ["en", "fr"],
                country: "FR",
                totalUsers: 1234,
                totalVideos: 5678,
                totalLocalVideos: 4500,
                health: 100,
                createdAt: "2020-01-01"
            ),
            isAlreadyAdded: false,
            onAdd: {}
        )

        PeerTubeDirectoryRow(
            instance: PeerTubeDirectoryInstance(
                id: 2,
                host: "video.example.org",
                name: "Another Instance",
                shortDescription: nil,
                version: "4.5.0",
                signupAllowed: false,
                languages: ["de"],
                country: "DE",
                totalUsers: 500,
                totalVideos: 1200,
                totalLocalVideos: 800,
                health: 95,
                createdAt: "2021-06-15"
            ),
            isAlreadyAdded: true,
            onAdd: {}
        )
    }
}
