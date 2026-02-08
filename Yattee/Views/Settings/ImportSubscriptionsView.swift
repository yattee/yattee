//
//  ImportSubscriptionsView.swift
//  Yattee
//
//  View for importing subscriptions from an Invidious or Piped instance to local storage.
//

import SwiftUI

struct ImportSubscriptionsView: View {
    let instance: Instance

    @Environment(\.appEnvironment) private var appEnvironment

    @State private var channels: [Channel] = []
    @State private var subscribedChannelIDs: Set<String> = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showAddAllConfirmation = false

    // MARK: - Accessibility Identifiers

    private enum AccessibilityID {
        static let view = "import.subscriptions.view"
        static let loadingIndicator = "import.subscriptions.loading"
        static let errorMessage = "import.subscriptions.error"
        static let emptyState = "import.subscriptions.empty"
        static let list = "import.subscriptions.list"
        static func row(_ channelID: String) -> String {
            "import.subscriptions.row.\(channelID)"
        }
        static func addButton(_ channelID: String) -> String {
            "import.subscriptions.add.\(channelID)"
        }
        static func subscribedIndicator(_ channelID: String) -> String {
            "import.subscriptions.subscribed.\(channelID)"
        }
        static let addAllButton = "import.subscriptions.addAll"
    }

    // MARK: - Body

    var body: some View {
        content
            .navigationTitle(String(localized: "import.subscriptions.title"))
            .accessibilityIdentifier(AccessibilityID.view)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !unsubscribedChannels.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddAllConfirmation = true
                        } label: {
                            Label(String(localized: "import.subscriptions.addAll"), systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier(AccessibilityID.addAllButton)
                    }
                }
            }
            .confirmationDialog(
                String(localized: "import.subscriptions.addAllConfirmation \(unsubscribedChannels.count)"),
                isPresented: $showAddAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "import.subscriptions.addAll")) {
                    addAllSubscriptions()
                }
            }
            .task {
                await loadSubscriptions()
            }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let error {
            errorView(error)
        } else if channels.isEmpty {
            emptyView
        } else {
            listView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(String(localized: "import.subscriptions.loading"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.loadingIndicator)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(String(localized: "import.subscriptions.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await loadSubscriptions() }
            }
            .buttonStyle(.bordered)
        }
        .accessibilityIdentifier(AccessibilityID.errorMessage)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            String(localized: "import.subscriptions.emptyTitle"),
            systemImage: "person.2.slash",
            description: Text(String(localized: "import.subscriptions.emptyDescription"))
        )
        .accessibilityIdentifier(AccessibilityID.emptyState)
    }

    private var listView: some View {
        List {
            ForEach(channels) { channel in
                subscriptionRow(channel)
                    .accessibilityIdentifier(AccessibilityID.row(channel.id.channelID))
            }
        }
        .accessibilityIdentifier(AccessibilityID.list)
    }

    // MARK: - Row View

    @ViewBuilder
    private func subscriptionRow(_ channel: Channel) -> some View {
        HStack(spacing: 12) {
            // Channel avatar
            if let avatarURL = channel.thumbnailURL {
                AsyncImage(url: avatarURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }

            // Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(channel.name)
                        .lineLimit(1)

                    if channel.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let subscriberCount = channel.formattedSubscriberCount {
                    Text(subscriberCount)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Add/Subscribed indicator
            if subscribedChannelIDs.contains(channel.id.channelID) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
                    .accessibilityIdentifier(AccessibilityID.subscribedIndicator(channel.id.channelID))
            } else {
                Button {
                    addSubscription(channel)
                } label: {
                    Image(systemName: "plus.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier(AccessibilityID.addButton(channel.id.channelID))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Computed Properties

    private var unsubscribedChannels: [Channel] {
        channels.filter { !subscribedChannelIDs.contains($0.id.channelID) }
    }

    // MARK: - Actions

    private func loadSubscriptions() async {
        guard let appEnvironment,
              let credential = appEnvironment.credentialsManager(for: instance)?.credential(for: instance) else {
            error = ImportError.notLoggedIn
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            let fetchedChannels: [Channel]

            switch instance.type {
            case .invidious:
                let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
                let subscriptions = try await api.subscriptions(instance: instance, sid: credential)
                fetchedChannels = subscriptions.map { $0.toChannel(baseURL: instance.url) }

            case .piped:
                let api = PipedAPI(httpClient: appEnvironment.httpClient)
                let subscriptions = try await api.subscriptions(instance: instance, authToken: credential)
                fetchedChannels = subscriptions.map { $0.toChannel() }

            default:
                throw ImportError.notSupported
            }

            channels = fetchedChannels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Get already-subscribed channel IDs
            subscribedChannelIDs = Set(
                appEnvironment.dataManager.subscriptions().map(\.channelID)
            )

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func addSubscription(_ channel: Channel) {
        guard let dataManager = appEnvironment?.dataManager else { return }

        dataManager.subscribe(to: channel)
        subscribedChannelIDs.insert(channel.id.channelID)

        appEnvironment?.toastManager.showSuccess(String(localized: "import.subscriptions.added.title"))
    }

    private func addAllSubscriptions() {
        guard let dataManager = appEnvironment?.dataManager else { return }

        let toAdd = unsubscribedChannels
        for channel in toAdd {
            dataManager.subscribe(to: channel)
            subscribedChannelIDs.insert(channel.id.channelID)
        }

        appEnvironment?.toastManager.showSuccess(
            String(localized: "import.subscriptions.added.title"),
            subtitle: String(localized: "import.subscriptions.count.subtitle \(toAdd.count)")
        )
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case notLoggedIn
        case notSupported

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return String(localized: "import.subscriptions.notLoggedIn")
            case .notSupported:
                return String(localized: "import.subscriptions.notSupported")
            }
        }
    }
}

// MARK: - Preview

#Preview("Invidious") {
    NavigationStack {
        ImportSubscriptionsView(
            instance: Instance(type: .invidious, url: URL(string: "https://invidious.example.com")!)
        )
        .appEnvironment(.preview)
    }
}

#Preview("Piped") {
    NavigationStack {
        ImportSubscriptionsView(
            instance: Instance(type: .piped, url: URL(string: "https://piped.example.com")!)
        )
        .appEnvironment(.preview)
    }
}
