//
//  ReturnYouTubeDislikeSettingsView.swift
//  Yattee
//
//  Return YouTube Dislike settings.
//

import SwiftUI

struct ReturnYouTubeDislikeSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        Form {
            if let settings = appEnvironment?.settingsManager {
                // Enable/Disable toggle
                Section {
                    Toggle(
                        String(localized: "settings.returnYouTubeDislike.enabled"),
                        isOn: Bindable(settings).returnYouTubeDislikeEnabled
                    )
                } footer: {
                    Text(String(localized: "settings.returnYouTubeDislike.footer"))
                }

                // About section
                Section(String(localized: "settings.returnYouTubeDislike.about.header")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.returnYouTubeDislike.about.description"))
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Link(destination: URL(string: "https://returnyoutubedislike.com")!) {
                            HStack {
                                Text(String(localized: "settings.returnYouTubeDislike.learnMore"))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.returnYouTubeDislike.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ReturnYouTubeDislikeSettingsView()
    }
    .appEnvironment(.preview)
}
