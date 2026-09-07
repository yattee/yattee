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
            HStack(spacing: 6) {
                // The same checkmark the switcher marks the selected context
                // with — the row's menu offers "Use this account" on every
                // other account, and the row it is missing from has to say why.
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
        .contextMenu {
            // Selecting an account from the source that owns it, rather than
            // hunting for it in the global switcher.
            if !isCurrentContext(account) {
                Button {
                    appEnvironment?.switchDataContext(to: .account(account.id))
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
                pendingSignOut = account
            } label: {
                Label(String(localized: "login.signOutAndRemove"), systemImage: "rectangle.portrait.and.arrow.forward")
            }
        }
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
