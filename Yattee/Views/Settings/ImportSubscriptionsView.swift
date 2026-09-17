//
//  ImportSubscriptionsView.swift
//  Yattee
//
//  View for importing subscriptions from an Invidious or Piped instance into a
//  chosen destination: the local store, or another logged-in account.
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

    @State private var selectedDestination: DataContext = .local
    @State private var destinationSeeded = false
    /// Channels with a subscribe in flight, so a slow server write cannot be
    /// double-tapped into two requests.
    @State private var pendingChannelIDs: Set<String> = []
    @State private var isAddingAll = false

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
        static let destinationPicker = "import.subscriptions.destination"
    }

    // MARK: - Body

    var body: some View {
        content
            #if !os(tvOS)
            .navigationTitle(String(localized: "import.subscriptions.title"))
            #endif
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
                        .disabled(isAddingAll)
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
            .presentationCompactAdaptation(.sheet)
            .task {
                seedDestination()
                await loadSubscriptions()
            }
            // Re-asked per destination: the marks describe where the channels
            // would be added, not where they came from.
            .task(id: selectedDestination) {
                await refreshSubscribedChannelIDs()
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.errorMessage)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            String(localized: "import.subscriptions.emptyTitle"),
            systemImage: "person.2.slash",
            description: Text(String(localized: "import.subscriptions.emptyDescription"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.emptyState)
    }

    private var listView: some View {
        List {
            if destinations.count > 1 {
                Section {
                    destinationPicker
                        .accessibilityIdentifier(AccessibilityID.destinationPicker)
                }
            }

            Section {
                ForEach(channels) { channel in
                    subscriptionRow(channel)
                        .accessibilityIdentifier(AccessibilityID.row(channel.id.channelID))
                }
            }
        }
        .opaqueSettingsFormBackground()
        .accessibilityIdentifier(AccessibilityID.list)
    }

    // MARK: - Destination Picker

    private var destinationPicker: some View {
        #if os(tvOS)
        // A tvOS menu picker shows only its value; the name of the control has
        // to be the row's own — the same shape as the playlist selector's.
        Menu {
            Picker(selection: $selectedDestination) {
                destinationOptionRows
            } label: {}
        } label: {
            HStack {
                Text(String(localized: "accounts.switcher.title"))
                Spacer(minLength: 8)
                Text(DataContextSwitcherLabels.title(for: selectedDestination, in: appEnvironment))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        #else
        Picker(String(localized: "accounts.switcher.title"), selection: $selectedDestination) {
            destinationOptionRows
        }
        .pickerStyle(.menu)
        #endif
    }

    @ViewBuilder private var destinationOptionRows: some View {
        ForEach(destinations, id: \.self) { context in
            Text(DataContextSwitcherLabels.title(for: context, in: appEnvironment))
                .tag(context)
        }
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
            } else if pendingChannelIDs.contains(channel.id.channelID) {
                ProgressView()
            } else {
                Button {
                    addSubscription(channel)
                } label: {
                    Image(systemName: "plus.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .disabled(isAddingAll)
                .accessibilityIdentifier(AccessibilityID.addButton(channel.id.channelID))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Computed Properties

    private var unsubscribedChannels: [Channel] {
        channels.filter { !subscribedChannelIDs.contains($0.id.channelID) }
    }

    /// The account whose list is being imported. Its context is not offered as
    /// a destination — every channel is already subscribed there.
    private var sourceAccountContext: DataContext? {
        guard let appEnvironment,
              let account = appEnvironment.account(forInstance: instance) else { return nil }
        return .account(account.id)
    }

    /// Where the channels can be added: the same destinations a subscribe menu
    /// offers, minus the source itself.
    private var destinations: [DataContext] {
        SubscriptionDestinations.available(in: appEnvironment)
            .filter { $0 != sourceAccountContext }
    }

    // MARK: - Actions

    /// Opens on the account being browsed when it is a valid target, otherwise
    /// local — which always is.
    private func seedDestination() {
        guard !destinationSeeded else { return }
        destinationSeeded = true

        guard let current = appEnvironment?.accountsManager.currentContext,
              !current.isLocal,
              destinations.contains(current)
        else { return }

        selectedDestination = current
    }

    private func loadSubscriptions() async {
        guard let appEnvironment,
              let credential = appEnvironment.credential(forInstance: instance) else {
            error = ImportError.notLoggedIn
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            guard instance.type.accountCapabilities.supportsSubscriptions else {
                throw ImportError.notSupported
            }

            let fetchedChannels = try await appEnvironment.contentService.subscriptions(
                for: instance,
                credential: credential
            )

            channels = fetchedChannels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    /// Marks the rows already subscribed on the selected destination.
    private func refreshSubscribedChannelIDs() async {
        guard let service = appEnvironment?.subscriptionService else { return }

        subscribedChannelIDs = []

        let destination = selectedDestination
        let ids = await service.subscribedChannelIDs(in: destination)

        guard destination == selectedDestination else { return }
        subscribedChannelIDs = ids ?? []
    }

    private func addSubscription(_ channel: Channel) {
        guard let appEnvironment else { return }

        let destination = selectedDestination
        let channelID = channel.id.channelID
        pendingChannelIDs.insert(channelID)

        Task {
            defer { pendingChannelIDs.remove(channelID) }

            do {
                try await appEnvironment.subscriptionService.subscribe(to: channel, in: destination)
            } catch SubscriptionProviderError.alreadySubscribed {
                // The mark below is the only correction needed.
            } catch {
                appEnvironment.toastManager.showError(
                    String(localized: "channel.subscribe.error.title"),
                    subtitle: error.localizedDescription
                )
                return
            }

            if destination == selectedDestination {
                subscribedChannelIDs.insert(channelID)
            }

            appEnvironment.toastManager.showSuccess(
                String(localized: "import.subscriptions.added.title"),
                subtitle: DataContextSwitcherLabels.title(for: destination, in: appEnvironment)
            )
        }
    }

    private func addAllSubscriptions() {
        guard let appEnvironment else { return }

        let destination = selectedDestination
        let toAdd = unsubscribedChannels
        isAddingAll = true

        Task {
            defer { isAddingAll = false }

            var added = 0
            var failed = 0

            // Serially: a server destination gets one request at a time, not a
            // burst the size of someone's subscription list.
            for channel in toAdd {
                let channelID = channel.id.channelID
                pendingChannelIDs.insert(channelID)
                defer { pendingChannelIDs.remove(channelID) }

                do {
                    try await appEnvironment.subscriptionService.subscribe(to: channel, in: destination)
                    added += 1
                } catch SubscriptionProviderError.alreadySubscribed {
                    added += 1
                } catch {
                    failed += 1
                    LoggingService.shared.error(
                        "Failed to import subscription \(channelID): \(error.localizedDescription)",
                        category: .general
                    )
                    continue
                }

                if destination == selectedDestination {
                    subscribedChannelIDs.insert(channelID)
                }
            }

            if failed > 0 {
                appEnvironment.toastManager.showError(
                    String(localized: "channel.subscribe.error.title"),
                    subtitle: String(localized: "import.subscriptions.count.subtitle \(added)")
                )
            } else {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "import.subscriptions.added.title"),
                    subtitle: String(localized: "import.subscriptions.count.subtitle \(added)")
                )
            }
        }
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
