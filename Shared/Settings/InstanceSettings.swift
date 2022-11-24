import SwiftUI

struct InstanceSettings: View {
    let instance: Instance

    @State private var accountsChanged = false
    @State private var presentingAccountForm = false

    @State private var frontendURL = ""
    @State private var proxiesVideos = false

    var body: some View {
        List {
            Section(header: Text("Accounts".localized())) {
                if instance.app.supportsAccounts {
                    ForEach(InstancesModel.shared.accounts(instance.id), id: \.self) { account in
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
                                    Button {
                                        removeAccount(account)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                        #endif
                    }
                    .redrawOn(change: accountsChanged)

                    Button {
                        presentingAccountForm = true
                    } label: {
                        Label("Add Account...", systemImage: "plus")
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
            if instance.app.hasFrontendURL {
                Section(header: Text("Frontend URL".localized())) {
                    TextField(
                        "Frontend URL",
                        text: $frontendURL
                    )
                    .onAppear {
                        frontendURL = instance.frontendURL ?? ""
                    }
                    .onChange(of: frontendURL) { newValue in
                        InstancesModel.shared.setFrontendURL(instance, newValue)
                    }
                    .labelsHidden()
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                }
            }

            if instance.app.allowsDisablingVidoesProxying {
                proxiesVideosToggle
                    .onAppear {
                        proxiesVideos = instance.proxiesVideos
                    }
                    .onChange(of: proxiesVideos) { newValue in
                        InstancesModel.shared.setProxiesVideos(instance, newValue)
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

    private var proxiesVideosToggle: some View {
        Toggle("Proxy videos", isOn: $proxiesVideos)
    }

    private func removeAccount(_ account: Account) {
        AccountsModel.remove(account)
        accountsChanged.toggle()
    }
}
