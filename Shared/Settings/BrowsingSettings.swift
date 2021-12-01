import Defaults
import SwiftUI

struct BrowsingSettings: View {
    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.saveRecents) private var saveRecents
    @Default(.saveHistory) private var saveHistory
    @Default(.visibleSections) private var visibleSections

    var body: some View {
        Group {
            Section(header: SettingsHeader(text: "Browsing")) {
                Toggle("Show channel name on thumbnail", isOn: $channelOnThumbnail)
                Toggle("Show video length on thumbnail", isOn: $timeOnThumbnail)
                Toggle("Save recent queries and channels", isOn: $saveRecents)
                Toggle("Save history of played videos", isOn: $saveHistory)
            }
            Section(header: SettingsHeader(text: "Sections")) {
                #if os(macOS)
                    let list = List(VisibleSection.allCases, id: \.self) { section in
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
