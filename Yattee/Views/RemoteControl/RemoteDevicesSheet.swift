//
//  RemoteDevicesSheet.swift
//  Yattee
//
//  Sheet for quickly accessing remote control devices from Home.
//

import SwiftUI

struct RemoteDevicesSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDevice: DiscoveredDevice?

    var body: some View {
        DynamicSheetContainer {
            NavigationStack {
                RemoteControlContentView(navigationStyle: .selection($selectedDevice))
                    .navigationTitle("Remote Control")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 300)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(role: .cancel) {
                                dismiss()
                            } label: {
                                Label("Close", systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                    .navigationDestination(item: $selectedDevice) { device in
                        RemoteControlView(device: device)
                    }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    RemoteDevicesSheet()
        .appEnvironment(.preview)
}
