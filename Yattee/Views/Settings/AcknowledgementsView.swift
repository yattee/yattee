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
        Form {
            Section {
                dependencyLink("mpv", url: "https://github.com/mpv-player/mpv")
                dependencyLink("MPVKit", url: "https://github.com/mpvkit/MPVKit")
                dependencyLink("Nuke", url: "https://github.com/kean/Nuke")
            } header: {
                Text(String(localized: "settings.acknowledgements.dependencies.header"))
            }
        }
        .navigationTitle(String(localized: "settings.acknowledgements.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func dependencyLink(_ name: String, url: String) -> some View {
        #if os(tvOS)
        Text(name)
        #else
        Button {
            if let url = URL(string: url) {
                openURL(url)
            }
        } label: {
            HStack {
                Text(name)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .foregroundStyle(.secondary)
            }
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
