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
                ForEach(instances.accounts(instanceID)) { account in
                    HStack(spacing: 2) {
                        Text(account.description)
                        if instances.defaultAccount == account {
                            Text("— default")
                                .foregroundColor(.secondary)
                        }
                    }
                    #if !os(tvOS)
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

    private func resetDefaultAccount() {
        instances.resetDefaultAccount()
        accountsChanged.toggle()
    }

    private func removeAccount(_ account: Instance.Account) {
        instances.removeAccount(account)
        accountsChanged.toggle()
    }
}
