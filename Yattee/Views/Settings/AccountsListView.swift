//
//  AccountsListView.swift
//  Yattee
//
//  Every account on this device, grouped by the source it lives on.
//

import SwiftUI

/// A login started from this screen.
///
/// Unlike the per-instance section, this one spans every source — so the
/// instance the sheet is for travels with the target rather than being a
/// property of the view.
private struct AccountsListLogin: Identifiable {
    let id: UUID
    let instance: Instance
    let target: AccountLoginTarget
}

/// An account the user asked to remove, held until the confirmation comes back.
private struct PendingAccountRemoval: Identifiable {
    let id: UUID
    let name: String
    let isOrphan: Bool
}

/// The accounts screen: what is signed in where, and what to do about it.
///
/// The per-instance section in the source editor shows one server's logins
/// while the user is already editing it. This is the other direction — every
/// login the app knows about, including the ones whose source is gone and which
/// no source editor can reach.
struct AccountsListView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var login: AccountsListLogin?
    @State private var pendingRemoval: PendingAccountRemoval?
    @State private var renameRequest: AccountRenameRequest?

    #if os(tvOS)
    /// The account whose actions dialog is up. tvOS only: everywhere else the
    /// row grows a context menu instead of a press target.
    @State private var actionsAccountID: UUID?
    #endif

    /// Bumped whenever a credential is replaced, purely to re-read the login
    /// identifier the rows display.
    ///
    /// That identifier lives in the Keychain beside the secret, not in any
    /// observable state, so signing in again as somebody else moves nothing
    /// SwiftUI watches. The rest of the screen is driven by observation: the
    /// account list, the statuses and the instances are all observable, and
    /// rebuilding rows on every status change would cost tvOS its focus.
    @State private var credentialRevision = 0

    private var accountsManager: AccountsManager? {
        appEnvironment?.accountsManager
    }

    // MARK: - Body

    var body: some View {
        Group {
            #if os(tvOS)
            TVSidebarDetailContainer(
                systemImage: "person.crop.circle",
                title: String(localized: "accounts.title")
            ) {
                content
            }
            #else
            content
            #endif
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "accounts.title"))
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .platformSheet(item: $login) { login in
            loginSheet(login)
        }
        .confirmationDialog(
            pendingRemoval.map { String(localized: "accounts.remove.confirm.title \($0.name)") } ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.remove"), role: .destructive) {
                confirmRemoval()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingRemoval = nil
            }
        } message: {
            Text(
                String(
                    localized: pendingRemoval?.isOrphan == true
                        ? "accounts.remove.confirm.message.orphan"
                        : "accounts.remove.confirm.message"
                )
            )
        }
        #if !os(tvOS)
        .presentationCompactAdaptation(.sheet)
        #endif
        .accountRenameAlert($renameRequest) { accountID, name in
            appEnvironment?.accountsManager.updateDisplayName(name, for: accountID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            credentialRevision &+= 1
        }
        .accessibilityIdentifier("accounts.view")
    }

    @ViewBuilder
    private var content: some View {
        if accountsManager?.accounts.isEmpty ?? true {
            emptyState
        } else {
            Form {
                // The switcher lives here rather than beside the Accounts row
                // in Settings: which account is current is this screen's
                // subject, and the row below names the same account the
                // checkmarked row further down is marked as. Withheld while
                // every listed account is an orphan — there is nothing the
                // switcher could offer besides the local data the app is
                // already on.
                if DataContextSwitcherVisibility.showsSwitcher(in: appEnvironment) {
                    Section {
                        DataContextSwitcherSettingsRow()
                    } header: {
                        Text(String(localized: "accounts.switcher.section"))
                    }
                }

                ForEach(groups, id: \.instance.id) { group in
                    instanceSection(group.instance, accounts: group.accounts)
                }

                orphanSection

                pickerVisibilitySection
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .opaqueSettingsFormBackground()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "accounts.empty.title"), systemImage: "person.crop.circle")
        } description: {
            Text(String(localized: "accounts.empty.description"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sections

    /// Instances that hold at least one account, oldest source first.
    ///
    /// A source with no logins is left out: the place to make one is the source
    /// itself, and listing every server here would bury the accounts.
    private var groups: [(instance: Instance, accounts: [Account])] {
        guard let appEnvironment else { return [] }

        return appEnvironment.instancesManager.instances
            .sorted { $0.dateAdded < $1.dateAdded }
            .compactMap { instance in
                let accounts = sorted(appEnvironment.accountsManager.accounts(forInstance: instance.id))
                return accounts.isEmpty ? nil : (instance, accounts)
            }
    }

    /// Stable regardless of the order the accounts arrived from iCloud in.
    private func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted {
            ($0.dateAdded, $0.id.uuidString) < ($1.dateAdded, $1.id.uuidString)
        }
    }

    @ViewBuilder
    private func instanceSection(_ instance: Instance, accounts: [Account]) -> some View {
        Section {
            ForEach(accounts) { account in
                accountRow(account, instance: instance)
            }
            // Read here on purpose, so the rows genuinely depend on it rather
            // than relying on a state write invalidating a body that never
            // mentions it.
            .id(credentialRevision)
        } header: {
            HStack(spacing: 6) {
                Text(instance.displayName)

                // Said for the source as well as on each of its rows: without
                // it the section reads like a healthy server whose logins
                // happen to be unusable.
                if !instance.isEnabled {
                    Text(String(localized: "sources.status.disabled"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var orphanSection: some View {
        let orphans = sorted(accountsManager?.orphanedAccounts ?? [])

        if !orphans.isEmpty {
            Section {
                ForEach(orphans) { account in
                    accountRow(account, instance: nil)
                }
            } header: {
                Text(String(localized: "accounts.orphan.section"))
            } footer: {
                Text(String(localized: "accounts.orphan.footer"))
            }
        }
    }

    /// Whether the switcher is offered outside this screen at all — the
    /// toolbar menus, the tvOS buttons, the macOS sidebar row. Lives at the
    /// bottom of this screen because this screen keeps its own switcher either
    /// way: turning the pickers off must leave a place to turn them back on.
    @ViewBuilder
    private var pickerVisibilitySection: some View {
        if DataContextSwitcherVisibility.showsSwitcher(in: appEnvironment),
           let settings = appEnvironment?.settingsManager {
            @Bindable var settings = settings

            Section {
                Toggle(isOn: $settings.showAccountPickers) {
                    Label(
                        String(localized: "accounts.showPickers"),
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                }
            } footer: {
                Text(String(localized: "accounts.showPickers.footer"))
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func accountRow(_ account: Account, instance: Instance?) -> some View {
        #if os(tvOS)
        // One focusable row per account: pressing it raises the actions as a
        // dialog. Spelling them out as sibling rows made every account four
        // rows tall, which is a lot of clicking past on a remote.
        Button {
            actionsAccountID = account.id
        } label: {
            rowContent(account, instance: instance)
        }
        .buttonStyle(TVSettingsButtonStyle())
        .confirmationDialog(
            title(for: account, instance: instance),
            isPresented: Binding(
                // By ID: a label edit arriving from another device while the
                // dialog is up would otherwise close it.
                get: { actionsAccountID == account.id },
                set: { if !$0 { actionsAccountID = nil } }
            ),
            titleVisibility: .visible
        ) {
            rowActions(account, instance: instance)
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        #else
        rowContent(account, instance: instance)
            .contextMenu {
                rowActions(account, instance: instance)
            }
        #endif
    }

    private func rowContent(_ account: Account, instance: Instance?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // The same checkmark the switcher marks the selected context
                // with — this screen offers "Use this account" on every other
                // row, and the row it is missing from has to say why.
                if isCurrentContext(account) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel(String(localized: "accounts.current"))
                }

                Text(title(for: account, instance: instance))
                    .lineLimit(1)
            }

            if instance == nil {
                // An orphan has no status worth reporting: its capabilities are
                // unknown and no request can be made on its behalf. What it has
                // instead is the reason.
                Text(String(localized: "accounts.status.instanceMissing"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                AccountStatusBadge(status: status(for: account))
            }

            if let capabilities = capabilityHints(for: account) {
                Text(capabilities)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func rowActions(_ account: Account, instance: Instance?) -> some View {
        if let instance {
            if isSelectable(account), !isCurrentContext(account) {
                Button {
                    appEnvironment?.switchDataContext(to: .account(account.id))
                } label: {
                    Label(String(localized: "accounts.useThisAccount"), systemImage: "checkmark.circle")
                }
            }

            Button {
                login = AccountsListLogin(
                    id: account.id,
                    instance: instance,
                    target: .existing(account)
                )
            } label: {
                Label(String(localized: "login.signInAgain"), systemImage: "person.badge.key")
            }
        }

        // Offered on orphans too: with no source to fall back to, a label of
        // its own is the only thing that tells one abandoned login from another.
        Button {
            renameRequest = makeRenameRequest(for: account, instance: instance)
        } label: {
            Label(String(localized: "accounts.rename"), systemImage: "pencil")
        }

        // Not offered on an orphan: with no source there is nothing an active
        // account could do that an inactive one cannot.
        if instance != nil {
            Button {
                appEnvironment?.accountsManager.updateIsActive(!account.isActive, for: account.id)
            } label: {
                Label(
                    String(localized: account.isActive ? "accounts.deactivate" : "accounts.activate"),
                    systemImage: account.isActive
                        ? "person.crop.circle.badge.minus"
                        : "person.crop.circle.badge.checkmark"
                )
            }
        }

        Button(role: .destructive) {
            pendingRemoval = PendingAccountRemoval(
                id: account.id,
                name: title(for: account, instance: instance),
                isOrphan: instance == nil
            )
        } label: {
            Label(
                String(localized: instance == nil ? "common.remove" : "login.signOutAndRemove"),
                systemImage: instance == nil ? "trash" : "rectangle.portrait.and.arrow.forward"
            )
        }
    }

    private func loginSheet(_ login: AccountsListLogin) -> some View {
        InstanceLoginView(
            instance: login.instance,
            initialUsername: storedUsername(for: login.target)
        ) { credential, username in
            guard let appEnvironment else { return false }
            return AccountSignInHandler(appEnvironment: appEnvironment, instance: login.instance)
                .storeLogin(credential: credential, username: username, target: login.target)
        }
    }

    /// The identifier an existing account last signed in with, when this device
    /// holds it. A new account has nobody to name yet.
    private func storedUsername(for target: AccountLoginTarget) -> String? {
        guard let account = target.account else { return nil }
        return appEnvironment?.accountCredentialsManager(for: account)?.username(for: account)
    }

    // MARK: - Presentation

    /// The orphan's own label, never the validator's: with no instance to
    /// resolve, its last-resort fallback is the words "Source missing", which
    /// the row already says right underneath.
    private func title(for account: Account, instance: Instance?) -> String {
        guard instance != nil else {
            if let name = account.displayName, !name.isEmpty { return name }
            return String(localized: "accounts.orphan.unnamed")
        }

        return appEnvironment?.dataContextValidator.displayName(for: account)
            ?? String(localized: "accounts.orphan.unnamed")
    }

    /// What the rename field should start on, and what clearing it goes back to.
    ///
    /// An orphan is the exception for the same reason `title(for:instance:)`
    /// is: with no source to resolve through, the validator's last resort is
    /// the words "Source missing", which is a diagnosis and not a name to
    /// prefill a field with.
    private func makeRenameRequest(for account: Account, instance: Instance?) -> AccountRenameRequest {
        guard instance != nil, let validator = appEnvironment?.dataContextValidator else {
            return .forAccount(account, fallingBackTo: String(localized: "accounts.orphan.unnamed"))
        }

        return .forAccount(account, resolvedBy: validator)
    }

    /// The status the user is shown, not the credential's: a login on a source
    /// that has been switched off is not usable, whatever the Keychain says,
    /// and this screen already withholds "Use This Account" from it.
    private func status(for account: Account) -> AccountStatus {
        accountsManager?.displayStatus(for: account) ?? .checking
    }

    /// Asked of the validator rather than recomputed here: an account on a
    /// disabled source passes the capability test but is not something the
    /// switcher offers, and a screen that offered it would switch the app into
    /// a context that immediately falls back to local.
    private func isSelectable(_ account: Account) -> Bool {
        appEnvironment?.dataContextValidator.availableContexts.contains(.account(account.id)) == true
    }

    private func isCurrentContext(_ account: Account) -> Bool {
        accountsManager?.currentContext == .account(account.id)
    }

    /// What the backend behind this account lets it do. Deliberately a short
    /// sentence rather than a row of glyphs — the difference between two Piped
    /// logins is who they are, not what they support.
    ///
    /// Withheld while the source is switched off: none of it can be done until
    /// the user turns the source back on, and a row promising subscriptions,
    /// playlists and history directly under "Source switched off" contradicts
    /// the line above it.
    private func capabilityHints(for account: Account) -> String? {
        guard status(for: account) != .instanceDisabled else { return nil }
        guard let capabilities = accountsManager?.capabilities(for: account) else { return nil }

        var parts: [String] = []
        if capabilities.supportsSubscriptions {
            parts.append(String(localized: "accounts.capability.subscriptions"))
        }
        if capabilities.supportsPlaylistReads {
            parts.append(String(localized: "accounts.capability.playlists"))
        }
        if capabilities.supportsWatchHistory {
            parts.append(String(localized: "accounts.capability.history"))
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    /// Whether Settings should offer the entry at all.
    ///
    /// With no Invidious/Piped source added there is nothing this screen can
    /// do but explain itself, so the row waits for the first account-capable
    /// source. Existing accounts keep it visible regardless — an orphan whose
    /// source was deleted can only be cleaned up from here.
    @MainActor
    static func showsSettingsEntry(in appEnvironment: AppEnvironment?) -> Bool {
        guard let appEnvironment else { return false }

        return appEnvironment.instancesManager.hasAccountCapableInstances
            || !appEnvironment.accountsManager.accounts.isEmpty
    }

    /// Whether the settings entry should carry an attention badge.
    ///
    /// Both states the user can only clear from this screen: an orphan nothing
    /// else lists, and a login the server has started refusing.
    @MainActor
    static func needsAttention(in appEnvironment: AppEnvironment?) -> Bool {
        guard let appEnvironment else { return false }

        if !appEnvironment.accountsManager.orphanedAccounts.isEmpty { return true }

        return appEnvironment.accountsManager.accounts.contains {
            appEnvironment.accountsManager.status(for: $0.id) == .credentialRejected
        }
    }

    // MARK: - Actions

    private func confirmRemoval() {
        guard let appEnvironment, let pending = pendingRemoval else { return }
        defer { pendingRemoval = nil }

        // Re-resolved rather than trusted: the dialog can outlive the account,
        // which another device may have deleted while it was up.
        guard let account = appEnvironment.accountsManager.account(id: pending.id) else { return }

        if pending.isOrphan {
            appEnvironment.removeOrphanedAccount(account.id)
        } else {
            appEnvironment.signOutAndRemoveAccount(account)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AccountsListView()
    }
    .appEnvironment(.preview)
}
