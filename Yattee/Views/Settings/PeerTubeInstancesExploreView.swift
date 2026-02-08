//
//  PeerTubeInstancesExploreView.swift
//  Yattee
//
//  View for browsing and adding PeerTube instances from the public directory.
//

import SwiftUI

struct PeerTubeInstancesExploreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    // All instances loaded from API
    @State private var allInstances: [PeerTubeDirectoryInstance] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var filters = PeerTubeDirectoryFilters()
    @State private var showFiltersSheet = false

    // Pagination for display (client-side)
    @State private var displayLimit = 50
    private let pageSize = 50

    // Cache for filter options
    @State private var availableLanguages: [String] = []
    @State private var availableCountries: [String] = []

    /// Filtered instances based on current filters and search
    private var filteredInstances: [PeerTubeDirectoryInstance] {
        var result = allInstances

        // Filter by search text
        let searchQuery = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        if !searchQuery.isEmpty {
            result = result.filter { instance in
                instance.name.lowercased().contains(searchQuery) ||
                instance.host.lowercased().contains(searchQuery) ||
                (instance.shortDescription?.lowercased().contains(searchQuery) ?? false)
            }
        }

        // Filter by language
        if let language = filters.language {
            result = result.filter { $0.languages.contains(language) }
        }

        // Filter by country
        if let country = filters.country {
            result = result.filter { $0.country == country }
        }

        return result
    }

    /// Instances to display (with pagination)
    private var displayedInstances: [PeerTubeDirectoryInstance] {
        Array(filteredInstances.prefix(displayLimit))
    }

    /// Whether more instances can be loaded
    private var hasMore: Bool {
        displayLimit < filteredInstances.count
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "peertube.explore.title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
                .searchable(text: $searchText, prompt: Text(String(localized: "peertube.explore.search")))
                .onChange(of: searchText) { _, _ in
                    // Reset display limit when search changes
                    displayLimit = pageSize
                }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
        .task {
            await loadAllInstances()
        }
        .sheet(isPresented: $showFiltersSheet) {
            PeerTubeFiltersSheet(
                filters: $filters,
                languages: availableLanguages,
                countries: availableCountries,
                onApply: {
                    // Reset display limit when filters change
                    displayLimit = pageSize
                }
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && allInstances.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, allInstances.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button(String(localized: "common.retry")) {
                    Task {
                        await loadAllInstances()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if displayedInstances.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "peertube.explore.noResults"), systemImage: "magnifyingglass")
            } description: {
                Text(String(localized: "peertube.explore.noResults.description"))
            }
        } else {
            instancesList
        }
    }

    private var instancesList: some View {
        List {
            // Instances
            ForEach(displayedInstances) { instance in
                PeerTubeDirectoryRow(
                    instance: instance,
                    isAlreadyAdded: isInstanceAdded(instance)
                ) {
                    addInstance(instance)
                }
            }

            // Load more indicator
            if hasMore {
                HStack {
                    Spacer()
                    Button(String(localized: "common.loadMore")) {
                        loadMore()
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                }
                .onAppear {
                    loadMore()
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(role: .cancel) {
                dismiss()
            } label: {
                Label(String(localized: "common.close"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showFiltersSheet = true
            } label: {
                Label(
                    String(localized: "peertube.explore.filters"),
                    systemImage: filters.isDefault ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                )
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllInstances() async {
        guard let appEnvironment else { return }
        let api = PeerTubeDirectoryAPI(httpClient: appEnvironment.httpClient)

        isLoading = true
        errorMessage = nil

        do {
            // Load all instances (API returns up to ~1700)
            let response = try await api.fetchInstances(start: 0, count: 2000)

            await MainActor.run {
                allInstances = response.data
                isLoading = false

                // Extract available languages and countries from the data
                var languages = Set<String>()
                var countries = Set<String>()
                for instance in response.data {
                    languages.formUnion(instance.languages)
                    if let country = instance.country, !country.isEmpty {
                        countries.insert(country)
                    }
                }
                availableLanguages = languages.sorted()
                availableCountries = countries.sorted()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadMore() {
        displayLimit += pageSize
    }

    // MARK: - Instance Management

    private func isInstanceAdded(_ directoryInstance: PeerTubeDirectoryInstance) -> Bool {
        guard let url = directoryInstance.url,
              let instancesManager = appEnvironment?.instancesManager else { return false }
        return instancesManager.instances.contains { $0.url.host == url.host }
    }

    private func addInstance(_ directoryInstance: PeerTubeDirectoryInstance) {
        guard let url = directoryInstance.url,
              let instancesManager = appEnvironment?.instancesManager else { return }

        let instance = Instance(
            type: .peertube,
            url: url,
            name: directoryInstance.name
        )
        instancesManager.add(instance)
    }
}

// MARK: - Preview

#Preview {
    PeerTubeInstancesExploreView()
        .appEnvironment(.preview)
}
