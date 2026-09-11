//
//  InstanceAccountsSection.swift
//  Yattee
//
//  The per-instance account list shown in EditSourceView.
//

import SwiftUI

/// Which account a login sheet is for. `account == nil` means "create a new one".
struct AccountLoginTarget: Identifiable {
    let id: UUID
    let account: Account?

    static let newAccount = AccountLoginTarget(id: UUID(), account: nil)
    static func existing(_ account: Account) -> AccountLoginTarget {
        AccountLoginTarget(id: account.id, account: account)
    }
}

/// Lists the accounts signed in on one instance.
///
/// Replaces the single "Log in / Log out" pair: an instance can now hold
/// several logins, each with its own credential and status.
struct InstanceAccountsSection: View {
    let instance: Instance
    @Binding var loginTarget: AccountLoginTarget?

    @Environment(\.appEnvironment) private var appEnvironment

    /// Bumped whenever a credential is replaced, purely to re-read the login
    /// identifier the rows display.
    ///
    /// That identifier lives in the Keychain beside the secret, not in any
    /// observable state, so signing in again as somebody else moves nothing
    /// SwiftUI watches — same account, same context, and the status was
    /// already `signedIn`. Without this the row keeps naming the previous
    /// person while the app is already serving the new one's data, which is
    /// exactly backwards: the label is the only thing telling two logins on
    /// one instance apart.
    @State private var credentialRevision = 0

    /// The account a sign-out was asked for, held until the confirmation comes
    /// back. Removing an account deletes its credential from every device
    /// sharing the Keychain, which is not something to do on one tap.
    @State private var pendingSignOut: Account?

    /// The account a rename was asked for. Like the sign-out above it, held on
    /// the section rather than the row, and matched back to a row by ID.
    @State private var renameRequest: AccountRenameRequest?

    private var accounts: [Account] {
        appEnvironment?.accountsManager.accounts(forInstance: instance.id) ?? []
    }

    var body: some View {
        Section {
            ForEach(accounts) { account in
                accountRow(account)
            }
            // Read here on purpose, so the rows genuinely depend on it rather
            // than relying on a state write invalidating a body that never
            // mentions it.
            .id(credentialRevision)

            Button {
                loginTarget = .newAccount
            } label: {
                Label(
                    String(localized: accounts.isEmpty ? "login.loginToAccount" : "accounts.addAccount"),
                    systemImage: "person.badge.plus"
                )
            }
            #if os(tvOS)
            .buttonStyle(TVSettingsButtonStyle())
            #endif
        } header: {
            Text(String(localized: "login.header.account"))
        } footer: {
            Text(footerText)
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            credentialRevision &+= 1
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // The same checkmark the switcher marks the selected context
                // with — every other account is offered "Use this account",
                // and the row it is missing from has to say why.
                if isCurrentContext(account) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel(String(localized: "accounts.current"))
                }

                Text(displayName(for: account))
                    .lineLimit(1)
            }

            AccountStatusBadge(status: status(for: account))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if !os(tvOS)
        .contextMenu {
            rowActions(account)
        }
        #endif
        // Attached to the row that raised it rather than to the section: a
        // presentation modifier on a `Section` inside a `Form` has no view of
        // its own to present from.
        .confirmationDialog(
            String(localized: "accounts.remove.confirm.title \(displayName(for: account))"),
            isPresented: Binding(
                // By ID: a label edit arriving from another device while the
                // dialog is up would otherwise close it.
                get: { pendingSignOut?.id == account.id },
                set: { if !$0 { pendingSignOut = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.remove"), role: .destructive) {
                confirmSignOut()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                pendingSignOut = nil
            }
        } message: {
            Text(String(localized: "accounts.remove.confirm.message"))
        }
        #if !os(tvOS)
        .presentationCompactAdaptation(.sheet)
        #endif
        // Attached to the row for the same reason the dialog above it is, and
        // narrowed to the row that raised it so only one alert is ever live.
        .accountRenameAlert(
            Binding(
                get: { renameRequest?.id == account.id ? renameRequest : nil },
                set: { if $0 == nil { renameRequest = nil } }
            )
        ) { accountID, name in
            appEnvironment?.accountsManager.updateDisplayName(name, for: accountID)
        }

        #if os(tvOS)
        // A context menu is not reachable on tvOS, and a Form row is a single
        // focusable unit — so the actions are rows of their own. Without them
        // the whole account is unreachable here: directional focus walks
        // straight past a row that is only text.
        rowActions(account)
        #endif
    }

    @ViewBuilder
    private func rowActions(_ account: Account) -> some View {
        // Selecting an account from the source that owns it, rather than
        // hunting for it in the global switcher.
        if !isCurrentContext(account) {
            Button {
                appEnvironment?.switchDataContext(to: .account(account.id))
            } label: {
                Label(String(localized: "accounts.useThisAccount"), systemImage: "checkmark.circle")
            }
            #if os(tvOS)
            .buttonStyle(TVSettingsButtonStyle())
            #endif
        }

        // tvOS never syncs app Keychain items, so an account that arrived from
        // another device is credential-less here until the user signs in on the
        // Apple TV itself — which is what this same action does.
        Button {
            loginTarget = .existing(account)
        } label: {
            #if os(tvOS)
            Label(
                String(
                    localized: status(for: account) == .credentialMissing
                        ? "accounts.signInOnThisDevice"
                        : "login.signInAgain"
                ),
                systemImage: "person.badge.key"
            )
            #else
            Label(String(localized: "login.signInAgain"), systemImage: "person.badge.key")
            #endif
        }
        #if os(tvOS)
        .buttonStyle(TVSettingsButtonStyle())
        #endif

        Button {
            renameRequest = makeRenameRequest(for: account)
        } label: {
            Label(String(localized: "accounts.rename"), systemImage: "pencil")
        }
        #if os(tvOS)
        .buttonStyle(TVSettingsButtonStyle())
        #endif

        Button(role: .destructive) {
            pendingSignOut = account
        } label: {
            Label(String(localized: "login.signOutAndRemove"), systemImage: "rectangle.portrait.and.arrow.forward")
        }
        #if os(tvOS)
        .buttonStyle(TVSettingsButtonStyle())
        #endif
    }

    // MARK: - Presentation

    /// What the section says under the rows.
    ///
    /// Read from the statuses, not from the count: this is the screen the user
    /// comes to in order to fix a login the server turned down, and a footer
    /// that only counts accounts tells them, right there, that they are logged
    /// in. The worst state on the list is the one that gets named — a rejected
    /// credential is something to act on, and it outranks a server that
    /// happens to be down.
    private var footerText: String {
        guard !accounts.isEmpty else {
            return String(localized: "login.footer.loginBenefits")
        }

        // `checking` counts as healthy: it is the absence of an answer, and a
        // footer that reacted to it would blink a warning at every launch.
        let unhealthy = accounts.map { status(for: $0) }
            .filter { $0 != .signedIn && $0 != .checking }

        guard !unhealthy.isEmpty else {
            return String(localized: "login.footer.loggedIn")
        }

        if unhealthy.contains(.credentialRejected) {
            return String(localized: "login.footer.credentialRejected")
        }

        if unhealthy.contains(.unreachable) {
            return String(localized: "login.footer.unreachable")
        }

        if unhealthy.contains(.credentialMissing) {
            return String(localized: "login.footer.credentialMissing")
        }

        // A state named after this was written. Saying only that something is
        // wrong is worth little, but it is true, and the rows above say what.
        return String(localized: "login.footer.accountUnusable")
    }

    private func displayName(for account: Account) -> String {
        appEnvironment?.dataContextValidator.displayName(for: account) ?? instance.displayName
    }

    /// What the rename field starts on, and what clearing it goes back to.
    ///
    /// The section always has its instance, so the only reason to name the
    /// fallback here is a missing environment, where the row's own label is
    /// already the instance's.
    private func makeRenameRequest(for account: Account) -> AccountRenameRequest {
        guard let validator = appEnvironment?.dataContextValidator else {
            return .forAccount(account, fallingBackTo: instance.displayName)
        }

        return .forAccount(account, resolvedBy: validator)
    }

    private func status(for account: Account) -> AccountStatus {
        appEnvironment?.accountsManager.status(for: account.id) ?? .checking
    }

    private func isCurrentContext(_ account: Account) -> Bool {
        appEnvironment?.accountsManager.currentContext == .account(account.id)
    }

    // MARK: - Actions

    private func confirmSignOut() {
        guard let appEnvironment, let account = pendingSignOut else { return }
        defer { pendingSignOut = nil }

        // Re-resolved rather than trusted: the dialog can outlive the account,
        // which another device may have deleted while it was up.
        guard let account = appEnvironment.accountsManager.account(id: account.id) else { return }

        appEnvironment.signOutAndRemoveAccount(account)
    }
}
