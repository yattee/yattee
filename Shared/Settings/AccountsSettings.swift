import SwiftUI

struct AccountsSettings: View {
    let instanceID: Instance.ID?

    @State private var accountsChanged = false
    @State private var presentingAccountForm = false

    @EnvironmentObject<AccountsModel> private var model
    @EnvironmentObject<InstancesModel> private var instances

    var instance: Instance! {
        InstancesModel.find(instanceID)
    }

    var body: some View {
        VStack {
            if instance.app.supportsAccounts {
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
                ForEach(InstancesModel.accounts(instanceID), id: \.self) { account in
                    #if os(tvOS)
                        Button(account.description) {}
                            .contextMenu {
                                Button("Remove", role: .destructive) { removeAccount(account) }
                                Button("Cancel", role: .cancel) {}
                            }
                    #else
                        Text(account.description)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Remove", role: .destructive) { removeAccount(account) }
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
            AccountForm(instance: instance)
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #elseif os(tvOS)
            .frame(maxWidth: 1000)
        #endif
    }

    private var sectionFooter: some View {
        #if os(iOS)
            Text("Swipe to remove account")
        #else
            Text("Tap and hold to remove account")
                .foregroundColor(.secondary)
        #endif
    }

    private func removeAccount(_ account: Account) {
        AccountsModel.remove(account)
        accountsChanged.toggle()
    }
}
