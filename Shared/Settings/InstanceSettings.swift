import SwiftUI

struct InstanceSettings: View {
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
                        text: $frontendURL
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
                    ForEach(InstancesModel.accounts(instanceID), id: \.self) { account in
                        #if os(tvOS)
                            Button(account.description) {}
                                .contextMenu {
                                    Button("Remove") { removeAccount(account) }
                                    Button("Cancel", role: .cancel) {}
                                }
                        #else
                            ZStack {
                                NavigationLink(destination: EmptyView()) {
                                    EmptyView()
                                }
                                .disabled(true)
                                .hidden()

                                HStack {
                                    Text(account.description)
                                    Spacer()
                                }
                                .contextMenu {
                                    Button("Remove") { removeAccount(account) }
                                }
                            }
                        #endif
                    }
                    .redrawOn(change: accountsChanged)

                    Button("Add account...") {
                        presentingAccountForm = true
                    }
                    .sheet(isPresented: $presentingAccountForm, onDismiss: { accountsChanged.toggle() }) {
                        AccountForm(instance: instance)
                    }
                    #if !os(tvOS)
                    .listStyle(.insetGrouped)
                    #endif
                } else {
                    Text("Accounts are not supported for the application of this instance")
                        .foregroundColor(.secondary)
                }
            }
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #elseif os(iOS)
        .listStyle(.insetGrouped)
        #endif

        .navigationTitle(instance.description)
    }

    private var sectionFooter: some View {
        if !instance.app.supportsAccounts {
            return Text("")
        }

        return Text("Tap and hold to remove account")
            .foregroundColor(.secondary)
    }

    private func removeAccount(_ account: Account) {
        AccountsModel.remove(account)
        accountsChanged.toggle()
    }
}
