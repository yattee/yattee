//
//  TranslationContributorsView.swift
//  Yattee
//
//  Displays Weblate translation contributors.
//

import NukeUI
import SwiftUI

struct TranslationContributorsView: View {
    @State private var contributors: [TranslationContributor] = []

    var body: some View {
        content
            .navigationTitle(String(localized: "settings.translators.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                contributors = TranslationContributorsLoader.load()
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if contributors.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "settings.translators.empty"), systemImage: "globe")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            contributorsList
        }
    }

    private var contributorsList: some View {
        Form {
            Section {
                ForEach(contributors) { contributor in
                    contributorRow(contributor)
                }
            } footer: {
                Text(String(localized: "settings.translators.section.footer"))
            }
        }
    }

    private func contributorRow(_ contributor: TranslationContributor) -> some View {
        HStack(spacing: 12) {
            // Avatar
            LazyImage(url: contributor.gravatarURL) { state in
                ZStack {
                    Circle()
                        .fill(.quaternary)
                        .overlay {
                            if state.image == nil {
                                Text(String(contributor.displayName.prefix(1).uppercased()))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                        }

                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            // Name and languages
            VStack(alignment: .leading, spacing: 2) {
                Text(contributor.displayName)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(contributor.languageSummary())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Total contributions badge
            Text("\(contributor.totalContributions)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }
}

#Preview {
    NavigationStack {
        TranslationContributorsView()
    }
}
