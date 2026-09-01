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
            Text(String(localized: accounts.isEmpty ? "login.footer.loginBenefits" : "login.footer.loggedIn"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            credentialRevision &+= 1
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayName(for: account))
                .lineLimit(1)

            Text(statusText(for: account))
                .font(.caption)
                .foregroundStyle(statusColor(for: account))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            // Without this a second login on an instance cannot be reached: the
            // legacy picker lists one entry per instance, so it always resolves
            // to whichever account was signed in first. The switcher that makes
            // this a first-class choice everywhere comes later; until then this
            // is what makes a second login usable at all.
            if !isCurrentContext(account) {
                Button {
                    appEnvironment?.accountsManager.setContext(.account(account.id))
                } label: {
                    Label(String(localized: "accounts.useThisAccount"), systemImage: "checkmark.circle")
                }
            }

            Button {
                loginTarget = .existing(account)
            } label: {
                Label(String(localized: "login.signInAgain"), systemImage: "person.badge.key")
            }

            Button(role: .destructive) {
                signOut(account)
            } label: {
                Label(String(localized: "login.signOutAndRemove"), systemImage: "rectangle.portrait.and.arrow.forward")
            }
        }

        #if os(tvOS)
        // tvOS never syncs app Keychain items, so an account that arrived from
        // another device is permanently credential-less here until the user
        // signs in on the Apple TV itself. Offer that directly rather than
        // leaving a status the user cannot act on.
        if status(for: account) == .credentialMissing {
            Button {
                loginTarget = .existing(account)
            } label: {
                Label(String(localized: "accounts.signInOnThisDevice"), systemImage: "person.badge.key")
            }
            .buttonStyle(TVSettingsButtonStyle())
        }
        #endif
    }

    // MARK: - Presentation

    private func displayName(for account: Account) -> String {
        appEnvironment?.dataContextValidator.displayName(for: account) ?? instance.displayName
    }

    private func status(for account: Account) -> AccountStatus {
        appEnvironment?.accountsManager.status(for: account.id) ?? .checking
    }

    private func statusText(for account: Account) -> String {
        switch status(for: account) {
        case .checking: String(localized: "accounts.status.checking")
        case .signedIn: String(localized: "accounts.status.signedIn")
        case .credentialMissing: String(localized: "accounts.status.credentialMissing")
        case .credentialRejected: String(localized: "accounts.status.credentialRejected")
        case .unreachable: String(localized: "accounts.status.unreachable")
        }
    }

    private func isCurrentContext(_ account: Account) -> Bool {
        appEnvironment?.accountsManager.currentContext == .account(account.id)
    }

    private func statusColor(for account: Account) -> Color {
        switch status(for: account) {
        case .checking: .secondary
        case .signedIn: .secondary
        case .credentialMissing: .secondary
        case .credentialRejected: .red
        case .unreachable: .orange
        }
    }

    // MARK: - Actions

    private func signOut(_ account: Account) {
        guard let appEnvironment else { return }

        // Deleting the account is what authorizes removing the legacy item, and
        // only when this device adopted it and it still holds that same secret.
        appEnvironment.accountCredentialsManager(for: account)?.deleteCredential(for: account)
        appEnvironment.accountCredentialsManager(for: account)?.deleteLegacyCredentialIfOwned(for: account)
        appEnvironment.accountsManager.removeAccount(account.id)
        // Drop the provider too, or its in-memory subscription cache would keep
        // answering for an account that no longer exists.
        appEnvironment.subscriptionService.discardProvider(for: account.id)

        if appEnvironment.accountsManager.accounts(forInstance: instance.id).isEmpty {
            appEnvironment.instancesManager.setUsesAccountLogin(false, for: instance)
        }
    }
}
