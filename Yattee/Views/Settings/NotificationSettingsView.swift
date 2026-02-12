//
//  NotificationSettingsView.swift
//  Yattee
//
//  Settings view for background notifications configuration.
//

import SwiftUI
import NukeUI

struct NotificationSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var authorizationChecked = false

    var body: some View {
        Form {
            if let settings = appEnvironment?.settingsManager,
               let notificationManager = appEnvironment?.notificationManager {
                // Master toggle section
                EnableSection(
                    settings: settings,
                    notificationManager: notificationManager,
                    appEnvironment: appEnvironment
                )

                // Permission status section
                if authorizationChecked {
                    PermissionSection(notificationManager: notificationManager)
                }

                // Default for new subscriptions
                if settings.backgroundNotificationsEnabled {
                    DefaultsSection(settings: settings)

                    // Manage channels section
                    ManageChannelsSection()
                }
            }
        }
        .navigationTitle(String(localized: "settings.notifications.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await appEnvironment?.notificationManager.refreshAuthorizationStatus()
            authorizationChecked = true
        }
    }
}

// MARK: - Enable Section

private struct EnableSection: View {
    @Bindable var settings: SettingsManager
    let notificationManager: NotificationManager
    let appEnvironment: AppEnvironment?

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.notifications.enable"),
                isOn: Binding(
                    get: { settings.backgroundNotificationsEnabled },
                    set: { newValue in
                        if newValue {
                            enableNotifications()
                        } else {
                            disableNotifications()
                        }
                    }
                )
            )
        } footer: {
            Text(String(localized: "settings.notifications.footer"))
        }
    }

    private func enableNotifications() {
        Task {
            let granted = await notificationManager.requestAuthorization()
            if granted {
                settings.backgroundNotificationsEnabled = true
                appEnvironment?.backgroundRefreshManager.handleNotificationsEnabledChanged(true)
            }
        }
    }

    private func disableNotifications() {
        settings.backgroundNotificationsEnabled = false
        appEnvironment?.backgroundRefreshManager.handleNotificationsEnabledChanged(false)
    }
}

// MARK: - Permission Section

private struct PermissionSection: View {
    let notificationManager: NotificationManager

    var body: some View {
        Section {
            HStack {
                Text(String(localized: "settings.notifications.permission"))
                Spacer()
                if notificationManager.isAuthorized {
                    HStack(spacing: 4) {
                        Text(String(localized: "settings.notifications.permission.granted"))
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.green)
                } else {
                    Button(String(localized: "settings.notifications.openSettings")) {
                        notificationManager.openNotificationSettings()
                    }
                }
            }
        }
    }
}

// MARK: - Defaults Section

private struct DefaultsSection: View {
    @Bindable var settings: SettingsManager

    var body: some View {
        Section {
            Toggle(
                String(localized: "settings.notifications.defaultForNew"),
                isOn: $settings.defaultNotificationsForNewChannels
            )
        } header: {
            Text(String(localized: "settings.notifications.defaults.header"))
        } footer: {
            Text(String(localized: "settings.notifications.defaultForNew.footer"))
        }
    }
}

// MARK: - Manage Channels Section

private struct ManageChannelsSection: View {
    var body: some View {
        Section {
            NavigationLink {
                ManageChannelNotificationsView()
            } label: {
                Label(
                    String(localized: "settings.notifications.manageChannels"),
                    systemImage: "bell.badge"
                )
            }
        }
    }
}

// MARK: - Manage Channel Notifications View

struct ManageChannelNotificationsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var subscriptions: [Subscription] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshID = UUID()

    private var subscriptionService: SubscriptionService? { appEnvironment?.subscriptionService }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(
                        String(localized: "settings.notifications.loadError.title"),
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text(errorMessage)
                }
            } else if subscriptions.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: "settings.notifications.noSubscriptions.title"),
                        systemImage: "person.2.slash"
                    )
                } description: {
                    Text(String(localized: "settings.notifications.noSubscriptions.description"))
                }
            } else {
                ForEach(subscriptions, id: \.channelID) { subscription in
                    ChannelNotificationToggle(subscription: subscription)
                }
                .id(refreshID)
            }
        }
        .navigationTitle(String(localized: "settings.notifications.manageChannels.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if !subscriptions.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            setAllNotifications(enabled: true)
                        } label: {
                            Label(String(localized: "settings.notifications.enableAll"), systemImage: "bell.fill")
                        }
                        Button {
                            setAllNotifications(enabled: false)
                        } label: {
                            Label(String(localized: "settings.notifications.disableAll"), systemImage: "bell.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            await loadSubscriptionsAsync()
        }
    }

    private func setAllNotifications(enabled: Bool) {
        guard let dataManager = appEnvironment?.dataManager else { return }
        for subscription in subscriptions {
            dataManager.setNotificationsEnabled(enabled, for: subscription.channelID)
        }
        refreshID = UUID()
    }

    /// Loads subscriptions from the current subscription account provider.
    /// For local accounts, loads from DataManager.
    /// For Invidious/Piped accounts, fetches from the respective API.
    private func loadSubscriptionsAsync() async {
        guard let appEnvironment, let subscriptionService else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // For local account, load from DataManager
        if appEnvironment.settingsManager.subscriptionAccount.type == .local {
            subscriptions = appEnvironment.dataManager.subscriptions()
            return
        }

        // For Invidious/Piped, fetch from service
        do {
            let channels = try await subscriptionService.fetchSubscriptions()
            subscriptions = channels.map { Subscription.from(channel: $0) }
        } catch {
            LoggingService.shared.error(
                "Failed to load subscriptions for notifications: \(error.localizedDescription)",
                category: .general
            )
            errorMessage = error.localizedDescription
            subscriptions = []
        }
    }
}

// MARK: - Channel Notification Toggle

private struct ChannelNotificationToggle: View {
    @Environment(\.appEnvironment) private var appEnvironment
    let subscription: Subscription
    @State private var notificationsEnabled: Bool = false

    private var yatteeServer: Instance? {
        appEnvironment?.instancesManager.enabledYatteeServerInstances.first
    }

    private var effectiveAvatarURL: URL? {
        AvatarURLBuilder.avatarURL(
            channelID: subscription.channelID,
            directURL: subscription.avatarURL,
            serverURL: yatteeServer?.url,
            size: 28
        )
    }

    private var authHeader: String? {
        guard let server = yatteeServer else { return nil }
        return appEnvironment?.yatteeServerCredentialsManager.basicAuthHeader(for: server)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { newValue in
                notificationsEnabled = newValue
                appEnvironment?.dataManager.setNotificationsEnabled(newValue, for: subscription.channelID)
            }
        )
    }

    var body: some View {
        Toggle(isOn: toggleBinding) {
            HStack(spacing: 10) {
                // Channel avatar
                LazyImage(request: AvatarURLBuilder.imageRequest(url: effectiveAvatarURL, authHeader: authHeader)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Circle()
                            .fill(.quaternary)
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())

                // Channel name
                Text(subscription.name)
                    .lineLimit(1)
            }
        }
        .onAppear {
            // Load initial value from ChannelNotificationSettings
            notificationsEnabled = appEnvironment?.dataManager.notificationsEnabled(for: subscription.channelID) ?? false
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
}
