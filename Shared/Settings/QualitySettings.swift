import Defaults
import SwiftUI

struct QualitySettings: View {
    @State private var presentingProfileForm = false
    @State private var editedProfileID: QualityProfile.ID?

    @EnvironmentObject<SettingsModel> private var settings

    @Default(.qualityProfiles) private var qualityProfiles
    @Default(.batteryCellularProfile) private var batteryCellularProfile
    @Default(.batteryNonCellularProfile) private var batteryNonCellularProfile
    @Default(.chargingCellularProfile) private var chargingCellularProfile
    @Default(.chargingNonCellularProfile) private var chargingNonCellularProfile

    var body: some View {
        VStack {
            #if os(macOS)
                sections

                Spacer()
            #else
                List {
                    sections
                }
            #endif
        }
        .sheet(isPresented: $presentingProfileForm) {
            QualityProfileForm(qualityProfileID: $editedProfileID)
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #elseif os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("Quality")
    }

    var sections: some View {
        Group {
            Group {
                #if os(tvOS)
                    Section(header: Text("Default Profile")) {
                        Text("\(QualityProfilesModel.shared.tvOSProfile?.description ?? "None")")
                    }
                #elseif os(iOS)
                    if UIDevice.current.hasCellularCapabilites {
                        Section(header: Text("Battery")) {
                            Picker("Wi-Fi", selection: $batteryNonCellularProfile) { profilePickerOptions }
                            Picker("Cellular", selection: $batteryCellularProfile) { profilePickerOptions }
                        }
                        Section(header: Text("Charging")) {
                            Picker("Wi-Fi", selection: $chargingNonCellularProfile) { profilePickerOptions }
                            Picker("Cellular", selection: $chargingCellularProfile) { profilePickerOptions }
                        }
                    } else {
                        nonCellularBatteryDevicesProfilesPickers
                    }
                #else
                    if Power.hasInternalBattery {
                        nonCellularBatteryDevicesProfilesPickers
                    } else {
                        Picker("Default", selection: $chargingNonCellularProfile) { profilePickerOptions }
                    }
                #endif
            }
            .disabled(qualityProfiles.isEmpty)
            Section(header: SettingsHeader(text: "Profiles"), footer: profilesFooter) {
                profilesList

                Button {
                    editedProfileID = nil
                    presentingProfileForm = true
                } label: {
                    Label("Add profile...", systemImage: "plus")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button {
                    settings.presentAlert(
                        Alert(
                            title: Text("Are you sure you want to restore default quality profiles?"),
                            message: Text("This will remove all your custom profiles and return their default values. This cannot be reverted."),
                            primaryButton: .destructive(Text("Reset")) {
                                QualityProfilesModel.shared.reset()
                            },
                            secondaryButton: .cancel()
                        )
                    )
                } label: {
                    Text("Restore default profiles...")
                        .foregroundColor(.red)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder var nonCellularBatteryDevicesProfilesPickers: some View {
        Picker("Battery", selection: $batteryNonCellularProfile) { profilePickerOptions }
        Picker("Charging", selection: $chargingNonCellularProfile) { profilePickerOptions }
    }

    @ViewBuilder func profileControl(_ qualityProfile: QualityProfile) -> some View {
        #if os(tvOS)
            Button {
                QualityProfilesModel.shared.applyToAll(qualityProfile)
            } label: {
                Text(qualityProfile.description)
            }
        #else
            Text(qualityProfile.description)
        #endif
    }

    var profilePickerOptions: some View {
        ForEach(qualityProfiles) { qualityProfile in
            Text(qualityProfile.description).tag(qualityProfile.id)
        }
    }

    var profilesFooter: some View {
        #if os(tvOS)
            Text("You can switch between profiles in playback settings controls.")
        #else
            Text("You can use automatic profile selection based on current device status or switch it in video playback settings controls.")
                .foregroundColor(.secondary)
        #endif
    }

    @ViewBuilder var profilesList: some View {
        let list = ForEach(qualityProfiles) { qualityProfile in
            profileControl(qualityProfile)
                .contextMenu {
                    Button {
                        QualityProfilesModel.shared.applyToAll(qualityProfile)
                    } label: {
                        #if os(tvOS)
                            Text("Make default")
                        #elseif os(iOS)
                            Label("Apply to all", systemImage: "wand.and.stars")
                        #else
                            if Power.hasInternalBattery {
                                Text("Apply to all")
                            } else {
                                Text("Make default")
                            }
                        #endif
                    }
                    Button {
                        editedProfileID = qualityProfile.id
                        presentingProfileForm = true
                    } label: {
                        Label("Edit...", systemImage: "pencil")
                    }

                    Button {
                        QualityProfilesModel.shared.remove(qualityProfile)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }

                    #if os(tvOS)
                        Button("Cancel", role: .cancel) {}
                    #endif
                }
        }

        if #available(macOS 12.0, *) {
            #if os(macOS)
                List {
                    list
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            #else
                list
            #endif
        } else {
            #if os(macOS)
                List {
                    list
                }
            #else
                list
            #endif
        }
    }
}

struct QualitySettings_Previews: PreviewProvider {
    static var previews: some View {
        #if os(macOS)
            QualitySettings()
        #else
            NavigationView {
                EmptyView()
                QualitySettings()
            }
            .navigationViewStyle(.stack)
        #endif
    }
}
