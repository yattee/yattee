import Defaults
import SwiftUI

struct InstancesSettingsView: View {
    @Default(.instances) private var instances
    @EnvironmentObject<InstancesModel> private var model

    @State private var selectedInstanceID: Instance.ID?
    @State private var selectedAccount: Instance.Account?

    @State private var presentingAccountForm = false
    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    @State private var presentingConfirmationDialog = false

    var body: some View {
        Section {
            Text("Instance")

            if !instances.isEmpty {
                Picker("Instance", selection: $selectedInstanceID) {
                    ForEach(instances) { instance in
                        Text(instance.description).tag(Optional(instance.id))
                    }
                }
                .labelsHidden()
            } else {
                Text("You have no instances configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !selectedInstance.isNil {
                Text("Accounts")
                List(selection: $selectedAccount) {
                    if accounts.isEmpty {
                        Text("You have no accounts for this instance")
                            .foregroundColor(.secondary)
                    }
                    ForEach(accounts) { account in
                        AccountSettingsView(account: account, selectedAccount: $selectedAccount)
                            .tag(account)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            if selectedInstance != nil {
                HStack {
                    Button("Add Account...") {
                        selectedAccount = nil
                        presentingAccountForm = true
                    }

                    Spacer()

                    Button("Remove Instance", role: .destructive) {
                        presentingConfirmationDialog = true
                    }
                    .confirmationDialog(
                        "Are you sure you want to remove \(selectedInstance!.description) instance?",
                        isPresented: $presentingConfirmationDialog
                    ) {
                        Button("Remove Instance", role: .destructive) {
                            model.remove(selectedInstance!)
                            selectedInstanceID = instances.last?.id
                        }
                    }

                    .foregroundColor(.red)
                }
            }

            Button("Add Instance...") {
                presentingInstanceForm = true
            }

            DefaultAccountHint()
                .padding(.top, 10)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

        .onAppear {
            selectedInstanceID = instances.first?.id
        }
        .sheet(isPresented: $presentingAccountForm) {
            AccountFormView(instance: selectedInstance, selectedAccount: $selectedAccount)
        }
        .sheet(isPresented: $presentingInstanceForm, onDismiss: setSelectedInstanceToFormInstance) {
            InstanceFormView(savedInstanceID: $savedFormInstanceID)
        }
    }

    private func setSelectedInstanceToFormInstance() {
        if let id = savedFormInstanceID {
            selectedInstanceID = id
            savedFormInstanceID = nil
        }
    }

    var selectedInstance: Instance! {
        model.find(selectedInstanceID)
    }

    private var accounts: [Instance.Account] {
        guard selectedInstance != nil else {
            return []
        }

        return model.accounts(selectedInstanceID)
    }
}

struct InstancesSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            InstancesSettingsView()
        }
        .frame(width: 400, height: 270)
        .injectFixtureEnvironmentObjects()
    }
}
