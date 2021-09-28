import SwiftUI

struct InstanceDetailsSettingsView: View {
    let instanceID: Instance.ID?

    @State private var accountsChanged = false
    @State private var presentingAccountForm = false

    @EnvironmentObject<InstancesModel> private var instances

    var instance: Instance! {
        instances.find(instanceID)
    }

    var body: some View {
        List {
            Section(header: Text("Accounts")) {
                ForEach(instances.accounts(instanceID), id: \.self) { account in

                    #if !os(tvOS)
                        HStack(spacing: 2) {
                            Text(account.description)
                            if instances.defaultAccount == account {
                                Text("— default")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if instances.defaultAccount != account {
                                Button("Make Default", action: { makeDefault(account) })
                            } else {
                                Button("Reset Default", action: resetDefaultAccount)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", role: .destructive, action: { removeAccount(account) })
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
                            Button("Toggle Default", action: { toggleDefault(account) })
                            Button("Remove", role: .destructive, action: { removeAccount(account) })
                        }
                    #endif
                }
                .redrawOn(change: accountsChanged)

                Button("Add account...") {
                    presentingAccountForm = true
                }
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #elseif os(tvOS)
            .frame(maxWidth: 1000)
        #endif

        .navigationTitle(instance.shortDescription)
            .sheet(isPresented: $presentingAccountForm, onDismiss: { accountsChanged.toggle() }) {
                AccountFormView(instance: instance)
            }
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
