import SwiftUI

struct AccountsSettings: View {
    let instanceID: Instance.ID?

    @State private var accountsChanged = false
    @State private var presentingAccountForm = false

    @State private var frontendURL = ""

    @EnvironmentObject<AccountsModel> private var model
    @EnvironmentObject<InstancesModel> private var instances

    var instance: Instance! {
        InstancesModel.find(instanceID)
    }

    var body: some View {
        List {
            if instance.app.hasFrontendURL {
                Section(header: Text("Frontend URL")) {
                    TextField(
                        "Frontend URL",
                        text: $frontendURL,
                        prompt: Text("To enable videos, channels and playlists sharing")
                    )
                    .onAppear {
                        frontendURL = instance.frontendURL ?? ""
                    }
                    .onChange(of: frontendURL) { newValue in
                        InstancesModel.setFrontendURL(instance, newValue)
                    }
                    .labelsHidden()
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                }
            }

            Section(header: Text("Accounts"), footer: sectionFooter) {
                if instance.app.supportsAccounts {
                    accounts
                } else {
                    Text("Accounts are not supported for the application of this instance")
                        .foregroundColor(.secondary)
                }
            }
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #endif

        .navigationTitle(instance.description)
    }

    var accounts: some View {
        Group {
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
        .sheet(isPresented: $presentingAccountForm, onDismiss: { accountsChanged.toggle() }) {
            AccountForm(instance: instance)
        }
        #if !os(tvOS)
        .listStyle(.insetGrouped)
        #endif
    }

    private var sectionFooter: some View {
        if !instance.app.supportsAccounts {
            return Text("")
        }

        #if os(iOS)
            return Text("Swipe to remove account")
        #else
            return Text("Tap and hold to remove account")
                .foregroundColor(.secondary)
        #endif
    }

    private func removeAccount(_ account: Account) {
        AccountsModel.remove(account)
        accountsChanged.toggle()
    }
}
