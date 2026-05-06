//
//  AcknowledgementsView.swift
//  Yattee
//
//  Lists dependencies and open source libraries used in the app.
//

import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsFormContainer {
            SettingsFormSection("settings.acknowledgements.dependencies.header") {
                dependencyLink("mpv", url: "https://github.com/mpv-player/mpv")
                dependencyLink("MPVKit", url: "https://github.com/mpvkit/MPVKit")
                dependencyLink("Nuke", url: "https://github.com/kean/Nuke")
            }
        }
        .navigationTitle(String(localized: "settings.acknowledgements.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func dependencyLink(_ name: String, url: String) -> some View {
        Button {
            if let url = URL(string: url) {
                openURL(url)
            }
        } label: {
            HStack {
                Text(name)
                Spacer()
                #if !os(tvOS)
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
                #endif
            }
            .contentShape(Rectangle())
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
