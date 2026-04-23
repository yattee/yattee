//
//  ContributorsView.swift
//  Yattee
//
//  Displays GitHub contributors for the Yattee repository.
//

import NukeUI
import SwiftUI

struct ContributorsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var contributors: [GitHubContributor] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        content
            .navigationTitle(String(localized: "settings.contributors.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await loadContributors()
            }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && contributors.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, contributors.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(String(localized: "common.retry")) {
                    Task {
                        await loadContributors()
                    }
                }
                .buttonStyle(.borderedProminent)
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
                Text(String(localized: "settings.contributors.section.footer"))
            }
        }
    }

    private func contributorRow(_ contributor: GitHubContributor) -> some View {
        Button {
            if let url = contributor.profileURL {
                openURL(url)
            }
        } label: {
            HStack(spacing: 12) {
                // Avatar
                LazyImage(url: contributor.avatarURL) { state in
                    ZStack {
                        Circle()
                            .fill(.quaternary)
                            .overlay {
                                if state.image == nil {
                                    Text(String(contributor.login.prefix(1).uppercased()))
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

                // Username and commits
                VStack(alignment: .leading, spacing: 2) {
                    Text(contributor.login)
                        .font(.body)
                        .fontWeight(.semibold)

                    Text(String(localized: "settings.contributors.commits \(contributor.contributions)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data Loading

    private func loadContributors() async {
        guard let appEnvironment else { return }
        let api = GitHubAPI(httpClient: appEnvironment.httpClient)

        isLoading = true
        errorMessage = nil

        do {
            let result = try await api.contributors()
            await MainActor.run {
                contributors = result
                isLoading = false
            }
        } catch let error as APIError {
            await MainActor.run {
                if case .rateLimited = error {
                    errorMessage = String(localized: "settings.contributors.error.rateLimited")
                } else {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContributorsView()
    }
    .appEnvironment(.preview)
}
