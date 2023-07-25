import Defaults
import SwiftUI

struct LocationsSettings: View {
    @State private var countries = [String]()
    @State private var presentingInstanceForm = false
    @State private var savedFormInstanceID: Instance.ID?

    @ObservedObject private var accounts = AccountsModel.shared
    private var model = SettingsModel.shared

    @Default(.countryOfPublicInstances) private var countryOfPublicInstances
    @Default(.instances) private var instances
    @Default(.instancesManifest) private var instancesManifest

    var body: some View {
        VStack(alignment: .leading) {
            #if os(macOS)
                settings
                Spacer()
            #else
                List {
                    settings
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            #endif
        }
        .onAppear(perform: loadCountries)
        .onChange(of: countryOfPublicInstances) { newCountry in
            InstancesManifest.shared.setPublicAccount(newCountry, asCurrent: accounts.current?.isPublic ?? true)
        }
        .onChange(of: instancesManifest) { _ in
            countryOfPublicInstances = nil
            if let account = accounts.current, account.isPublic {
                accounts.setCurrent(nil)
            }
            countries.removeAll()
        }
        .sheet(isPresented: $presentingInstanceForm) {
            InstanceForm(savedInstanceID: $savedFormInstanceID)
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #endif
        .navigationTitle("Locations")
    }

    @ViewBuilder var settings: some View {
        Section(header: SettingsHeader(text: "Locations Manifest".localized())) {
            TextField("URL", text: $instancesManifest)
            #if !os(macOS)
                .keyboardType(.URL)
                .autocapitalization(.none)
            #endif
                .disableAutocorrection(true)
            Button("Reload manifest", action: loadCountries)
                .disabled(instancesManifest.isEmpty)
        }
        .padding(.bottom, 4)

        if !InstancesManifest.shared.manifestURL.isNil {
            Section(header: SettingsHeader(text: "Public Locations".localized()), footer: countryFooter) {
                Picker("Country", selection: $countryOfPublicInstances) {
                    Text("Don't use public locations").tag(String?.none)
                    ForEach(countries, id: \.self) { country in
                        Text(country).tag(Optional(country))
                    }
                }
                #if os(tvOS)
                .pickerStyle(.inline)
                #endif
                .disabled(countries.isEmpty)

                Button {
                    InstancesManifest.shared.changePublicAccount()
                } label: {
                    if let account = accounts.current, account.isPublic {
                        Text("Switch to other public location")
                    } else {
                        Text("Switch to public locations")
                    }
                }
                .disabled(countryOfPublicInstances.isNil)
            }
        }

        Section(header: SettingsHeader(text: "Custom Locations".localized())) {
            #if os(macOS)
                InstancesSettings()
            #else
                ForEach(instances) { instance in
                    AccountsNavigationLink(instance: instance)
                }
                AddPublicInstanceButton()
                addInstanceButton
            #endif
        }
    }

    @ViewBuilder var countryFooter: some View {
        if let account = accounts.current {
            let locationType = account.isPublic ? (account.country ?? "Unknown") : "Custom".localized()
            let description = account.isPublic ? account.urlString : account.instance?.description ?? "unknown".localized()

            Text("Current: \(locationType)\n\(description)")
                .foregroundColor(.secondary)
            #if os(macOS)
                .padding(.bottom, 10)
            #endif
        }
    }

    func loadCountries() {
        InstancesManifest.shared.configure()
        InstancesManifest.shared.instancesList?.load()
            .onSuccess { response in
                if let instances: [ManifestedInstance] = response.typedContent() {
                    self.countries = instances.map(\.country).unique().sorted()
                }
            }
            .onFailure { _ in
                model.presentAlert(title: "Could not load locations manifest".localized())
            }
    }

    private var addInstanceButton: some View {
        Button {
            presentingInstanceForm = true
        } label: {
            Label("Add Location...", systemImage: "plus")
        }
    }
}

struct LocationsSettings_Previews: PreviewProvider {
    static var previews: some View {
        LocationsSettings()
    }
}
