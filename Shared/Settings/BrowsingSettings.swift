import Defaults
import SwiftUI

struct BrowsingSettings: View {
    #if !os(tvOS)
        @Default(.accountPickerDisplaysUsername) private var accountPickerDisplaysUsername
    #endif
    #if os(iOS)
        @Default(.lockPortraitWhenBrowsing) private var lockPortraitWhenBrowsing
    #endif
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.visibleSections) private var visibleSections

    var body: some View {
        Group {
            Section(header: SettingsHeader(text: "Browsing")) {
                #if !os(tvOS)
                    Toggle("Show username in the account picker button", isOn: $accountPickerDisplaysUsername)
                #endif
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
                Toggle("Show channel name on thumbnail", isOn: $channelOnThumbnail)
                Toggle("Show video length on thumbnail", isOn: $timeOnThumbnail)
            }
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
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    func toggleSection(_ section: VisibleSection, value: Bool) {
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
