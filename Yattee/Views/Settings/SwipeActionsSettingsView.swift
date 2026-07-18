//
//  SwipeActionsSettingsView.swift
//  Yattee
//
//  Settings view for configuring video list swipe actions.
//

import SwiftUI

#if !os(tvOS)
struct SwipeActionsSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var actionOrder: [VideoSwipeAction] = []
    @State private var actionVisibility: [VideoSwipeAction: Bool] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(actionOrder, id: \.self) { action in
                    HStack {
                        Image(systemName: action.symbolImage)
                            .foregroundStyle(action.backgroundColor)
                            .frame(width: 24)

                        Text(action.displayName)

                        Spacer()

                        Toggle("", isOn: binding(for: action))
                            .labelsHidden()
                    }
                }
                .onMove(perform: moveAction)
            } header: {
                Text(String(localized: "settings.swipeActions.header"))
            } footer: {
                Text(String(localized: "settings.swipeActions.footer"))
            }
        }
        .navigationTitle(String(localized: "settings.swipeActions.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        #endif
        .onAppear {
            loadSettings()
        }
    }

    private func binding(for action: VideoSwipeAction) -> Binding<Bool> {
        Binding(
            get: { actionVisibility[action] ?? false },
            set: { newValue in
                actionVisibility[action] = newValue
                saveSettings()
            }
        )
    }

    private func moveAction(from source: IndexSet, to destination: Int) {
        actionOrder.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }

    private func loadSettings() {
        guard let settings = appEnvironment?.settingsManager else { return }
        actionOrder = settings.videoSwipeActionOrder
        actionVisibility = settings.videoSwipeActionVisibility
    }

    private func saveSettings() {
        guard let settings = appEnvironment?.settingsManager else { return }
        settings.videoSwipeActionOrder = actionOrder
        settings.videoSwipeActionVisibility = actionVisibility
    }
}

#Preview {
    NavigationStack {
        SwipeActionsSettingsView()
    }
    .appEnvironment(.preview)
}
#endif
