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
                ForEach(instance.accounts, id: \.self) { account in
                    Text(account.description)
                    #if !os(tvOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) {
                                instances.removeAccount(instance: instance, account: account)
                                accountsChanged.toggle()
                            }
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
}
