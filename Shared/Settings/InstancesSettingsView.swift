import Defaults
import SwiftUI

struct InstancesSettingsView: View {
    @Default(.instances) private var instances
    @EnvironmentObject<InstancesModel> private var instancesModel

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<SubscriptionsModel> private var subscriptions
    @EnvironmentObject<PlaylistsModel> private var playlists

    @State private var selectedInstanceID: Instance.ID?
    @State private var selectedAccount: Instance.Account?

    @State private var presentingAccountForm = false
    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    @State private var presentingConfirmationDialog = false
    @State private var presentingInstanceDetails = false

    var selectedInstance: Instance! {
        instancesModel.find(selectedInstanceID)
    }

    var body: some View {
        Group {
            #if os(iOS)
                Section(header: instancesHeader) {
                    ForEach(instances, id: \.self) { instance in
                        Button(action: {
                            self.selectedInstanceID = instance.id
                            self.presentingInstanceDetails = true
                        }) {
                            HStack {
                                Text(instance.description)
                                Spacer()
                                NavigationLink(
                                    isActive: .constant(false),
                                    destination: { EmptyView() },
                                    label: { EmptyView() }
                                )
                                .frame(maxWidth: 100)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", role: .destructive) {
                                instancesModel.remove(instance)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Add Instance...") {
                        presentingInstanceForm = true
                    }
                }
                .listStyle(.insetGrouped)
            #else
                Section {
                    Text("Instance")

                    if !instances.isEmpty {
                        Picker("Instance", selection: $selectedInstanceID) {
                            ForEach(instances, id: \.url) { instance in
                                Text(instance.description).tag(Optional(instance.id))
                            }
                        }
                        .labelsHidden()
                    } else {
                        Text("You have no instances configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let instance = selectedInstance {
                        if instance.accounts.isEmpty {
                            Text("You have no accounts for this instance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Accounts")
                            List(selection: $selectedAccount) {
                                ForEach(instance.accounts, id: \.self) { account in
                                    AccountSettingsView(instance: instance, account: account,
                                                        selectedAccount: $selectedAccount)
                                }
                            }
                            #if os(macOS)
                                .listStyle(.inset(alternatesRowBackgrounds: true))
                            #endif
                        }
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
                                    instancesModel.remove(selectedInstance!)
                                    selectedInstanceID = instances.last?.id
                                }
                            }

                            #if os(macOS)
                                .foregroundColor(.red)
                            #endif
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
                    AccountFormView(instance: selectedInstance, selectedAccount: $selectedAccount)
                }

                Spacer()

            #endif
        }
        .sheet(isPresented: $presentingInstanceForm, onDismiss: setSelectedInstanceToFormInstance) {
            InstanceFormView(savedInstanceID: $savedFormInstanceID)
        }
    }

    var instancesHeader: some View {
        Text("Instances").background(instanceDetailsNavigationLink)
    }

    var instanceDetailsNavigationLink: some View {
        NavigationLink(
            isActive: $presentingInstanceDetails,
            destination: { InstanceDetailsSettingsView(instanceID: selectedInstanceID) },
            label: { EmptyView() }
        )
    }

    func setSelectedInstanceToFormInstance() {
        if let id = savedFormInstanceID {
            selectedInstanceID = id
            savedFormInstanceID = nil
        }
    }
}

struct InstancesSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        InstancesSettingsView()
    }
}
