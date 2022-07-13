import Defaults
import SwiftUI

struct BrowsingSettings: View {
    #if !os(tvOS)
        @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername
        @Default(.roundedThumbnails) private var roundedThumbnails
    #endif
    #if os(iOS)
        @Default(.lockPortraitWhenBrowsing) private var lockPortraitWhenBrowsing
    #endif
    @Default(.thumbnailsQuality) private var thumbnailsQuality
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.visibleSections) private var visibleSections

    var body: some View {
        Group {
            #if os(macOS)
                sections
            #else
                List {
                    sections
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
            #endif
        }
        #if os(tvOS)
        .frame(maxWidth: 1000)
        #else
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        #endif
        .navigationTitle("Browsing")
    }

    private var sections: some View {
        Group {
            #if !os(tvOS)
                interfaceSettings
            #endif
            thumbnailsSettings
            visibleSectionsSettings
        }
    }

    private var interfaceSettings: some View {
        Section(header: SettingsHeader(text: "Interface")) {
            #if os(iOS)
                Toggle("Lock portrait mode", isOn: $lockPortraitWhenBrowsing)
                    .onChange(of: lockPortraitWhenBrowsing) { lock in
                        if lock {
                            Orientation.lockOrientation(.portrait, andRotateTo: .portrait)
                        } else {
                            Orientation.lockOrientation(.allButUpsideDown)
                        }
                    }
            #endif

            #if !os(tvOS)
                Toggle("Show account username", isOn: $accountPickerDisplaysUsername)
            #endif
        }
    }

    private var thumbnailsSettings: some View {
        Section(header: SettingsHeader(text: "Thumbnails")) {
            thumbnailsQualityPicker
            #if !os(tvOS)
                Toggle("Round corners", isOn: $roundedThumbnails)
            #endif
            Toggle("Show channel name", isOn: $channelOnThumbnail)
            Toggle("Show video length", isOn: $timeOnThumbnail)
        }
    }

    private var thumbnailsQualityPicker: some View {
        Picker("Quality", selection: $thumbnailsQuality) {
            ForEach(ThumbnailsQuality.allCases, id: \.self) { quality in
                Text(quality.rawValue.capitalized + " quality").tag(quality)
            }
        }
        .labelsHidden()

        #if os(iOS)
            .pickerStyle(.automatic)
        #elseif os(tvOS)
            .pickerStyle(.inline)
        #endif
    }

    private var visibleSectionsSettings: some View {
        Section(header: SettingsHeader(text: "Sections")) {
            #if os(macOS)
                let list = ForEach(VisibleSection.allCases, id: \.self) { section in
                    VisibleSectionSelectionRow(
                        title: section.title,
                        selected: visibleSections.contains(section)
                    ) { value in
                        toggleSection(section, value: value)
                    }
                }

                Group {
                    if #available(macOS 12.0, *) {
                        list
                            .listStyle(.inset(alternatesRowBackgrounds: true))
                    } else {
                        list
                            .listStyle(.inset)
                    }

                    Spacer()
                }
            #else
                ForEach(VisibleSection.allCases, id: \.self) { section in
                    VisibleSectionSelectionRow(
                        title: section.title,
                        selected: visibleSections.contains(section)
                    ) { value in
                        toggleSection(section, value: value)
                    }
                }
            #endif
        }
    }

    private func toggleSection(_ section: VisibleSection, value: Bool) {
        if value {
            visibleSections.insert(section)
        } else {
            visibleSections.remove(section)
        }
    }

    struct VisibleSectionSelectionRow: View {
        let title: String
        let selected: Bool
        var action: (Bool) -> Void

        @State private var toggleChecked = false

        var body: some View {
            Button(action: { action(!selected) }) {
                HStack {
                    #if os(macOS)
                        Toggle(isOn: $toggleChecked) {
                            Text(self.title)
                            Spacer()
                        }
                        .onAppear {
                            toggleChecked = selected
                        }
                        .onChange(of: toggleChecked) { new in
                            action(new)
                        }
                    #else
                        Text(self.title)
                        Spacer()
                        if selected {
                            Image(systemName: "checkmark")
                            #if os(iOS)
                                .foregroundColor(.accentColor)
                            #endif
                        }
                    #endif
                }
                .contentShape(Rectangle())
            }
            #if !os(tvOS)
            .buttonStyle(.plain)
            #endif
        }
    }
}

struct BrowsingSettings_Previews: PreviewProvider {
    static var previews: some View {
        BrowsingSettings()
            .injectFixtureEnvironmentObjects()
    }
}
