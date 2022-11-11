import Defaults
import SwiftUI

struct AdvancedSettings: View {
    @Default(.instancesManifest) private var instancesManifest
    @Default(.showMPVPlaybackStats) private var showMPVPlaybackStats
    @Default(.mpvCacheSecs) private var mpvCacheSecs
    @Default(.mpvCachePauseWait) private var mpvCachePauseWait
    @Default(.mpvEnableLogging) private var mpvEnableLogging
    @Default(.countryOfPublicInstances) private var countryOfPublicInstances
    @Default(.instances) private var instances

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<SettingsModel> private var settings

    @State private var countries = [String]()
    @State private var filesToShare = [MPVClient.logFile]
    @State private var presentingInstanceForm = false
    @State private var presentingShareSheet = false
    @State private var savedFormInstanceID: Instance.ID?

    var body: some View {
        VStack(alignment: .leading) {
            #if os(macOS)
                advancedSettings
                locationsSettings
                Spacer()
            #else
                List {
                    advancedSettings
                    locationsSettings
                }
                #if os(iOS)
                .sheet(isPresented: $presentingShareSheet) {
                    ShareSheet(activityItems: filesToShare)
                        .id("logs-\(filesToShare.count)")
                }
                .listStyle(.insetGrouped)
                #endif
            #endif
        }
        .onAppear(perform: loadCountries)
        .onChange(of: countryOfPublicInstances) { newCountry in
            InstancesManifest.shared.setPublicAccount(newCountry, accounts: accounts, asCurrent: accounts.current?.isPublic ?? true)
        }
        .onChange(of: instancesManifest) { _ in
            countries.removeAll()
        }
        .sheet(isPresented: $presentingInstanceForm) {
            InstanceForm(savedInstanceID: $savedFormInstanceID)
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #endif
        .navigationTitle("Advanced")
    }

    var logButton: some View {
        Button {
            #if os(macOS)
                NSWorkspace.shared.selectFile(MPVClient.logFile.path, inFileViewerRootedAtPath: YatteeApp.logsDirectory.path)
            #else
                presentingShareSheet = true
            #endif
        } label: {
            #if os(macOS)
                let labelText = "Open logs in Finder".localized()
            #else
                let labelText = "Share Logs...".localized()
            #endif
            Text(labelText)
        }
    }

    @ViewBuilder var advancedSettings: some View {
        Section(header: SettingsHeader(text: "MPV"), footer: mpvFooter) {
            showMPVPlaybackStatsToggle
            #if !os(tvOS)
                mpvEnableLoggingToggle
            #endif

            HStack {
                Text("cache-secs")
                    .frame(minWidth: 140, alignment: .leading)
                TextField("cache-secs", text: $mpvCacheSecs)
            }
            .multilineTextAlignment(.trailing)

            HStack {
                Text("cache-pause-wait")
                    .frame(minWidth: 140, alignment: .leading)
                TextField("cache-pause-wait", text: $mpvCachePauseWait)
            }
            .multilineTextAlignment(.trailing)

            if mpvEnableLogging {
                logButton
            }
        }

        Section(header: manifestHeader) {
            TextField("URL", text: $instancesManifest)
            Button("Reload manifest", action: loadCountries)
                .disabled(instancesManifest.isEmpty)
            #if !os(macOS)
                .keyboardType(.webSearch)
            #endif
                .disableAutocorrection(true)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder var mpvFooter: some View {
        let url = "https://mpv.io/manual/master"

        VStack(alignment: .leading) {
            Text("Restart the app to apply the settings above.")
            VStack(alignment: .leading, spacing: 2) {
                #if os(tvOS)
                    Text("More info can be found in MPV Documentation:")
                    Text(url)
                #else
                    Text("More info can be found in:")
                    Link("MPV Documentation", destination: URL(string: url)!)
                    #if os(macOS)
                        .onHover(perform: onHover(_:))
                    #endif
                #endif
            }
        }
        .foregroundColor(.secondary)
    }

    var manifestHeader: some View {
        SettingsHeader(text: "Locations Manifest".localized())
    }

    var showMPVPlaybackStatsToggle: some View {
        Toggle("Show playback statistics", isOn: $showMPVPlaybackStats)
    }

    var mpvEnableLoggingToggle: some View {
        Toggle("Enable logging", isOn: $mpvEnableLogging)
    }

    #if os(macOS)
        private func onHover(_ inside: Bool) {
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    #endif

    @ViewBuilder var locationsSettings: some View {
        if !InstancesManifest.shared.manifestURL.isNil, !countries.isEmpty {
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
                    InstancesManifest.shared.changePublicAccount(accounts, settings: settings)
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
                    .environmentObject(settings)
            #else
                ForEach(instances) { instance in
                    AccountsNavigationLink(instance: instance)
                }
                addInstanceButton
            #endif
        }
    }

    @ViewBuilder var countryFooter: some View {
        if let account = accounts.current {
            let locationType = account.isPublic ? (account.country ?? "Unknown") : "Custom".localized()
            let description = account.isPublic ? account.url : account.instance?.description ?? "unknown".localized()

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
                settings.presentAlert(title: "Could not load locations manifest".localized())
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

struct AdvancedSettings_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettings()
            .injectFixtureEnvironmentObjects()
    }
}
