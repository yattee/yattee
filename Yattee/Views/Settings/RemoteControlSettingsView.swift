//
//  RemoteControlSettingsView.swift
//  Yattee
//
//  Settings for remote control configuration.
//

import SwiftUI

struct RemoteControlSettingsView: View {
    var body: some View {
        RemoteControlContentView(navigationStyle: .link)
            .navigationTitle(String(localized: "remoteControl.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RemoteControlSettingsView()
    }
    .appEnvironment(.preview)
}
