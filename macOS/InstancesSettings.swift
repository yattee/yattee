import Defaults
import SwiftUI

struct InstancesSettings: View {
    @State private var selectedInstanceID: Instance.ID?
    @State private var selectedAccount: Account?

    @State private var presentingAccountForm = false
    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    @State private var frontendURL = ""
    @State private var proxiesVideos = false

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var accounts = AccountsModel.shared
    private var settings = SettingsModel.shared

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
                SettingsHeader(text: "Accounts".localized())

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
                                settings.presentAlert(
                                    Alert(
                                        title: Text(
                                            "Are you sure you want to remove \(selectedAccount?.description ?? "") account?"
                                        ),
                                        message: Text("This cannot be reverted"),
                                        primaryButton: .destructive(Text("Remove")) {
                                            AccountsModel.remove(selectedAccount!)
                                        },
                                        secondaryButton: .cancel()
                                    )
                                )
                            }
                            .foregroundColor(colorScheme == .dark ? .white : .red)
                            .opacity(account == selectedAccount ? 1 : 0)
                        }
                        .tag(account)
                    }
                }

                if #available(macOS 12.0, *) {
                    list
                        .listStyle(.inset(alternatesRowBackgrounds: true))
                } else {
                    list
                }
            }

            if selectedInstance != nil, selectedInstance.app.hasFrontendURL {
                SettingsHeader(text: "Frontend URL".localized())

                TextField("Frontend URL", text: $frontendURL)
                    .onChange(of: selectedInstance) { _ in
                        frontendURL = selectedInstanceFrontendURL
                    }
                    .onChange(of: frontendURL) { newValue in
                        InstancesModel.shared.setFrontendURL(selectedInstance, newValue)
                    }
                    .labelsHidden()

                Text("Used to create links from videos, channels and playlists")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if selectedInstance != nil, selectedInstance.app.allowsDisablingVidoesProxying {
                proxiesVideosToggle
                    .onAppear {
                        proxiesVideos = selectedInstance.proxiesVideos
                    }
                    .onChange(of: proxiesVideos) { newValue in
                        InstancesModel.shared.setProxiesVideos(selectedInstance, newValue)
                    }
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
                        settings.presentAlert(Alert(
                            title: Text(String(
                                format: "Are you sure you want to remove %@ location?",
                                selectedInstance?.longDescription ?? ""
                            )),
                            message: Text("This cannot be reverted"),
                            primaryButton: .destructive(Text("Remove")) {
                                if accounts.current?.instance == selectedInstance {
                                    accounts.setCurrent(nil)
                                }

                                InstancesModel.shared.remove(selectedInstance!)
                                selectedInstanceID = instances.last?.id
                            },
                            secondaryButton: .cancel()
                        ))
                    }
                    .foregroundColor(.red)
                }
            }

            HStack {
                Button("Add Location...") {
                    presentingInstanceForm = true
                }
                Spacer()
                AddPublicInstanceButton()
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
        InstancesModel.shared.find(selectedInstanceID)
    }

    var selectedInstanceFrontendURL: String {
        selectedInstance?.frontendURL ?? ""
    }

    private var selectedInstanceAccounts: [Account] {
        guard selectedInstance != nil else {
            return []
        }

        return InstancesModel.shared.accounts(selectedInstanceID)
    }

    private var proxiesVideosToggle: some View {
        Toggle("Proxy videos", isOn: $proxiesVideos)
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
