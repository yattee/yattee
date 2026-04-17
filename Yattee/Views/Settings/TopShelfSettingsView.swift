//
//  TopShelfSettingsView.swift
//  Yattee
//
//  tvOS-only Top Shelf configuration.
//

#if os(tvOS)
import SwiftUI

struct TopShelfSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Form {
            if let settings = appEnvironment?.settingsManager {
                Section {
                    ForEach(TopShelfSection.allCases) { section in
                        Toggle(section.localizedTitle, isOn: binding(for: section, settings: settings))
                    }
                } header: {
                    Text(String(localized: "settings.topShelf.sections.header", defaultValue: "Sections"))
                } footer: {
                    Text(String(
                        localized: "settings.topShelf.sections.footer",
                        defaultValue: "Enabled sections appear in the Apple TV Home top shelf when Yattee is focused."
                    ))
                }
            }
        }
    }

    private func binding(for section: TopShelfSection, settings: SettingsManager) -> Binding<Bool> {
        Binding(
            get: { settings.topShelfSections.contains(section) },
            set: { enabled in
                var sections = settings.topShelfSections
                if enabled {
                    if !sections.contains(section) {
                        let defaultIndex = TopShelfSection.defaultOrder.firstIndex(of: section) ?? sections.endIndex
                        let insertAt = min(defaultIndex, sections.count)
                        sections.insert(section, at: insertAt)
                    }
                } else {
                    sections.removeAll { $0 == section }
                }
                settings.topShelfSections = sections
            }
        )
    }
}
#endif
