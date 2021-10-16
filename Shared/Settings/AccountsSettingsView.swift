import SwiftUI

struct AccountsSettingsView: View {
    let instanceID: Instance.ID?

    @State private var accountsChanged = false
    @State private var presentingAccountForm = false

    @EnvironmentObject<InstancesModel> private var instances

    var instance: Instance! {
        instances.find(instanceID)
    }

    var body: some View {
        Group {
            if instance.supportsAccounts {
                accounts
            } else {
                Text("Accounts are not supported for the application of this instance")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle(instance.shortDescription)
    }

    var accounts: some View {
        List {
            Section(header: Text("Accounts"), footer: sectionFooter) {
                ForEach(instances.accounts(instanceID), id: \.self) { account in
                    #if os(iOS)
                        HStack(spacing: 2) {
                            Text(account.description)
                            if instances.defaultAccount == account {
                                Text("— default")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if instances.defaultAccount != account {
                                Button("Make Default") { makeDefault(account) }
                            } else {
                                Button("Reset Default", action: resetDefaultAccount)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) { removeAccount(account) }
                        }

                    #else
                        Button(action: { toggleDefault(account) }) {
                            HStack(spacing: 2) {
                                Text(account.description)
                                if instances.defaultAccount == account {
                                    Text("— default")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Toggle Default") { toggleDefault(account) }
                            Button("Remove", role: .destructive) { removeAccount(account) }
                            Button("Cancel", role: .cancel) {}
                        }
                    #endif
                }
                .redrawOn(change: accountsChanged)

                Button("Add account...") {
                    presentingAccountForm = true
                }
            }
        }
        .sheet(isPresented: $presentingAccountForm, onDismiss: { accountsChanged.toggle() }) {
            AccountFormView(instance: instance)
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #elseif os(tvOS)
            .frame(maxWidth: 1000)
        #endif
    }

    private var sectionFooter: some View {
        #if os(iOS)
            Text("Swipe right to toggle default account, swipe left to remove")
        #else
            Text("Tap to toggle default account, tap and hold to remove")
                .foregroundColor(.secondary)
        #endif
    }

    private func makeDefault(_ account: Instance.Account) {
        instances.setDefaultAccount(account)
        accountsChanged.toggle()
    }

    private func toggleDefault(_ account: Instance.Account) {
        if account == instances.defaultAccount {
            resetDefaultAccount()
        } else {
            makeDefault(account)
        }
    }

    private func resetDefaultAccount() {
        instances.resetDefaultAccount()
        accountsChanged.toggle()
    }

    private func removeAccount(_ account: Instance.Account) {
        instances.removeAccount(account)
        accountsChanged.toggle()
    }
}
