import Defaults
import SwiftUI

struct InstancesSettings: View {
    @State private var selectedInstanceID: Instance.ID?
    @State private var selectedAccount: Account?

    @State private var presentingAccountForm = false
    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    @State private var presentingAccountRemovalConfirmation = false
    @State private var presentingInstanceRemovalConfirmation = false

    @State private var frontendURL = ""

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<InstancesModel> private var model

    @Default(.instances) private var instances

    var body: some View {
        Group {
            SettingsHeader(text: "Instance")

            if !instances.isEmpty {
                Picker("Instance", selection: $selectedInstanceID) {
                    ForEach(instances) { instance in
                        Text(instance.longDescription).tag(Optional(instance.id))
                    }
                }
                .labelsHidden()
            } else {
                Text("You have no instances configured")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            if !selectedInstance.isNil, selectedInstance.app.supportsAccounts {
                SettingsHeader(text: "Accounts")

                List(selection: $selectedAccount) {
                    if selectedInstanceAccounts.isEmpty {
                        Text("You have no accounts for this instance")
                            .foregroundColor(.secondary)
                    }
                    ForEach(selectedInstanceAccounts) { account in
                        HStack {
                            Text(account.description)

                            Spacer()

                            Button("Remove", role: .destructive) {
                                presentingAccountRemovalConfirmation = true
                            }
                            .foregroundColor(.red)
                            .opacity(account == selectedAccount ? 1 : 0)
                        }
                        .tag(account)
                    }
                }
                .confirmationDialog(
                    "Are you sure you want to remove \(selectedAccount?.description ?? "") account?",
                    isPresented: $presentingAccountRemovalConfirmation
                ) {
                    Button("Remove", role: .destructive) {
                        AccountsModel.remove(selectedAccount!)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            if selectedInstance != nil, selectedInstance.app.hasFrontendURL {
                SettingsHeader(text: "Frontend URL")

                TextField("Frontend URL", text: $frontendURL, prompt: Text("Frontend URL"))
                    .onAppear {
                        frontendURL = selectedInstance.frontendURL ?? ""
                    }
                    .onChange(of: frontendURL) { newValue in
                        InstancesModel.setFrontendURL(selectedInstance, newValue)
                    }
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 0) {
                    Text("If provided, you can copy links from videos, channels and playlist using")
                        .padding(.trailing, 2)

                    HStack(spacing: 0) {
                        Image(systemName: "command")

                        Text("**+C**")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()
            }

            if selectedInstance != nil, !selectedInstance.app.supportsAccounts {
                Spacer()
                Text("Accounts are not supported for the application of this instance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if selectedInstance != nil {
                HStack {
                    Button("Add Account...") {
                        selectedAccount = nil
                        presentingAccountForm = true
                    }
                    .disabled(!selectedInstance.app.supportsAccounts)

                    Spacer()

                    Button("Remove Instance", role: .destructive) {
                        presentingInstanceRemovalConfirmation = true
                    }
                    .confirmationDialog(
                        "Are you sure you want to remove \(selectedInstance!.longDescription) instance?",
                        isPresented: $presentingInstanceRemovalConfirmation
                    ) {
                        Button("Remove Instance", role: .destructive) {
                            if accounts.current?.instance == selectedInstance {
                                accounts.setCurrent(nil)
                            }

                            InstancesModel.remove(selectedInstance!)
                            selectedInstanceID = instances.last?.id
                        }
                    }

                    .foregroundColor(.red)
                }
            }

            Button("Add Instance...") {
                presentingInstanceForm = true
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

        .onAppear {
            selectedInstanceID = instances.first?.id
        }
        .sheet(isPresented: $presentingAccountForm) {
            AccountForm(instance: selectedInstance, selectedAccount: $selectedAccount)
        }
        .sheet(isPresented: $presentingInstanceForm, onDismiss: setSelectedInstanceToFormInstance) {
            InstanceForm(savedInstanceID: $savedFormInstanceID)
        }
    }

    private func setSelectedInstanceToFormInstance() {
        if let id = savedFormInstanceID {
            selectedInstanceID = id
            savedFormInstanceID = nil
        }
    }

    var selectedInstance: Instance! {
        InstancesModel.find(selectedInstanceID)
    }

    private var selectedInstanceAccounts: [Account] {
        guard selectedInstance != nil else {
            return []
        }

        return InstancesModel.accounts(selectedInstanceID)
    }
}

struct InstancesSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            InstancesSettings()
        }
        .frame(width: 400, height: 270)
        .injectFixtureEnvironmentObjects()
    }
}
