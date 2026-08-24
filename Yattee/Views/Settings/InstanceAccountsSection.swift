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

    private var accounts: [Account] {
        appEnvironment?.accountsManager.accounts(forInstance: instance.id) ?? []
    }

    var body: some View {
        Section {
            ForEach(accounts) { account in
                accountRow(account)
            }

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

        adoptionSection
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

    /// The one-tap adoption of a login saved by an earlier version.
    ///
    /// Shown only when such an item exists and has not been adopted. It is a
    /// deliberate action because a retained Keychain item carries no proof of
    /// which Apple Account it belonged to — the app cannot tell an inherited
    /// credential from the user's own.
    @ViewBuilder
    private var adoptionSection: some View {
        let adoptable = accounts.filter { account in
            appEnvironment?
                .accountCredentialsManager(for: account)?
                .hasAdoptableLegacyCredential(for: account) == true
        }

        if !adoptable.isEmpty {
            Section {
                ForEach(adoptable) { account in
                    Button {
                        adoptLegacyCredential(for: account)
                    } label: {
                        Label(String(localized: "accounts.useSavedLogin"), systemImage: "key.horizontal")
                    }
                    #if os(tvOS)
                    .buttonStyle(TVSettingsButtonStyle())
                    #endif
                }
            } footer: {
                Text(String(localized: "accounts.useSavedLogin.footer"))
            }
        }
    }

    // MARK: - Presentation

    private func displayName(for account: Account) -> String {
        appEnvironment?.dataContextValidator.displayName(for: account) ?? instance.displayName
    }

    private func status(for account: Account) -> AccountStatus {
        appEnvironment?.accountsManager.status(for: account.id) ?? .credentialMissing
    }

    private func statusText(for account: Account) -> String {
        switch status(for: account) {
        case .signedIn: String(localized: "accounts.status.signedIn")
        case .credentialMissing: String(localized: "accounts.status.credentialMissing")
        case .credentialRejected: String(localized: "accounts.status.credentialRejected")
        case .unreachable: String(localized: "accounts.status.unreachable")
        }
    }

    private func statusColor(for account: Account) -> Color {
        switch status(for: account) {
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

    private func adoptLegacyCredential(for account: Account) {
        guard let appEnvironment,
              let credentials = appEnvironment.accountCredentialsManager(for: account)
        else { return }

        if credentials.adoptLegacyCredential(for: account) {
            appEnvironment.accountsManager.setStatus(.signedIn, for: account.id)
        } else {
            appEnvironment.toastManager.showError(
                String(localized: "accounts.useSavedLogin.failed")
            )
        }
    }
}
