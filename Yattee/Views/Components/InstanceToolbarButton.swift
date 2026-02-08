//
//  InstanceToolbarButton.swift
//  Yattee
//
//  A toolbar button that shows the current active instance and allows switching.
//

import SwiftUI

struct InstanceToolbarButton: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingPicker = false

    var body: some View {
        if let instancesManager = appEnvironment?.instancesManager,
           instancesManager.enabledInstances.count > 1 {
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: iconForInstance)
                    Text(instancesManager.activeInstance?.displayName ?? "")
                        .font(.subheadline)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
            }
            .sheet(isPresented: $showingPicker) {
                InstancePickerSheet()
            }
        }
    }

    private var iconForInstance: String {
        guard let instance = appEnvironment?.instancesManager.activeInstance else {
            return "server.rack"
        }
        return instance.type.systemImage
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Text("Content")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    InstanceToolbarButton()
                }
            }
    }
    .appEnvironment(.preview)
}
