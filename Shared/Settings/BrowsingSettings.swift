import Defaults
import SwiftUI

struct BrowsingSettings: View {
    #if !os(tvOS)
        @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername
        @Default(.roundedThumbnails) private var roundedThumbnails
    #endif
    @Default(.accountPickerDisplaysAnonymousAccounts) private var accountPickerDisplaysAnonymousAccounts
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
            interfaceSettings
            thumbnailsSettings
            visibleSectionsSettings
        }
    }

    private var interfaceSettings: some View {
        Section(header: SettingsHeader(text: "Interface".localized())) {
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

            Toggle("Show anonymous accounts", isOn: $accountPickerDisplaysAnonymousAccounts)
        }
    }

    private var thumbnailsSettings: some View {
        Section(header: SettingsHeader(text: "Thumbnails".localized())) {
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
                Text(quality.description)
            }
        }
        .modifier(SettingsPickerModifier())
    }

    private var visibleSectionsSettings: some View {
        Section(header: SettingsHeader(text: "Sections".localized())) {
            #if os(macOS)
                let list = ForEach(VisibleSection.allCases, id: \.self) { section in
                    MultiselectRow(
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
                    MultiselectRow(
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
}

struct BrowsingSettings_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            BrowsingSettings()
        }
        .injectFixtureEnvironmentObjects()
    }
}
