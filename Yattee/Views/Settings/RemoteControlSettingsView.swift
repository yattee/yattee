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
            .navigationTitle("Remote Control")
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
