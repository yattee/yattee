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

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<SettingsModel> private var settings

    @Default(.instances) private var instances

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !instances.isEmpty {
                Picker("Instance", selection: $selectedInstanceID) {
                    ForEach(instances) { instance in
                        Text(instance.longDescription).tag(Optional(instance.id))
                    }
                }
                .labelsHidden()
            } else {
                Text("You have no custom locations configured")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            if !selectedInstance.isNil, selectedInstance.app.supportsAccounts {
                SettingsHeader(text: "Accounts")

                let list = List(selection: $selectedAccount) {
                    if selectedInstanceAccounts.isEmpty {
                        Text("You have no accounts for this location")
                            .foregroundColor(.secondary)
                    }
                    ForEach(selectedInstanceAccounts) { account in
                        HStack {
                            Text(account.description)

                            Spacer()

                            Button("Remove") {
                                presentingAccountRemovalConfirmation = true
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .red)
                            .opacity(account == selectedAccount ? 1 : 0)
                        }
                        .tag(account)
                    }
                }
                .alert(isPresented: $presentingAccountRemovalConfirmation) {
                    Alert(
                        title: Text(
                            "Are you sure you want to remove \(selectedAccount?.description ?? "") account?"
                        ),
                        message: Text("This cannot be undone"),
                        primaryButton: .destructive(Text("Remove")) {
                            AccountsModel.remove(selectedAccount!)
                        },
                        secondaryButton: .cancel()
                    )
                }

                if #available(macOS 12.0, *) {
                    list
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                } else {
                    list
                }
            }

            if selectedInstance != nil, selectedInstance.app.hasFrontendURL {
                SettingsHeader(text: "Frontend URL")

                TextField("Frontend URL", text: $frontendURL)
                    .onChange(of: selectedInstance) { _ in
                        frontendURL = selectedInstanceFrontendURL
                    }
                    .onChange(of: frontendURL) { newValue in
                        InstancesModel.setFrontendURL(selectedInstance, newValue)
                    }
                    .labelsHidden()

                Text("Used to create links from videos, channels and playlists")
                    .font(.caption)
                    .foregroundColor(.secondary)
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

                    Button("Remove Location") {
                        presentingInstanceRemovalConfirmation = true
                        settings.presentAlert(Alert(
                            title: Text(
                                "Are you sure you want to remove \(selectedInstance!.longDescription) location?"
                            ),
                            message: Text("This cannot be undone"),
                            primaryButton: .destructive(Text("Remove")) {
                                if accounts.current?.instance == selectedInstance {
                                    accounts.setCurrent(nil)
                                }

                                InstancesModel.remove(selectedInstance!)
                                selectedInstanceID = instances.last?.id
                            },
                            secondaryButton: .cancel()
                        ))
                    }
                    .foregroundColor(.red)
                }
            }

            Button("Add Location...") {
                presentingInstanceForm = true
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

        .onAppear {
            selectedInstanceID = instances.first?.id
            frontendURL = selectedInstanceFrontendURL
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

    var selectedInstanceFrontendURL: String {
        selectedInstance?.frontendURL ?? ""
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
