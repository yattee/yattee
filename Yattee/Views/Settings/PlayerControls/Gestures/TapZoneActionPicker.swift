//
//  TapZoneActionPicker.swift
//  Yattee
//
//  Picker for selecting and configuring a tap zone action.
//

#if os(iOS)
import SwiftUI

/// View for selecting and configuring a tap zone's action.
struct TapZoneActionPicker: View {
    let position: TapZonePosition
    @Binding var action: TapGestureAction

    @State private var selectedActionType: TapGestureActionType
    @State private var seekSeconds: Int

    init(position: TapZonePosition, action: Binding<TapGestureAction>) {
        self.position = position
        self._action = action
        self._selectedActionType = State(initialValue: action.wrappedValue.actionType)
        self._seekSeconds = State(initialValue: action.wrappedValue.seekSeconds ?? 10)
    }

    var body: some View {
        List {
            Section {
                ForEach(TapGestureActionType.allCases) { actionType in
                    Button {
                        selectedActionType = actionType
                        updateAction()
                    } label: {
                        HStack {
                            Label {
                                Text(actionType.displayName)
                            } icon: {
                                Image(systemName: actionType.systemImage)
                                    .foregroundStyle(.tint)
                            }

                            Spacer()

                            if selectedActionType == actionType {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(String(localized: "gestures.tap.selectAction", defaultValue: "Select Action"))
            }

            if selectedActionType.requiresSecondsParameter {
                Section {
                    seekSecondsControl
                } header: {
                    Text(String(localized: "gestures.tap.seekDuration", defaultValue: "Seek Duration"))
                }
            }
        }
        .navigationTitle(position.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private var seekSecondsControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "gestures.tap.seconds", defaultValue: "Seconds"))
                Spacer()
                Text("\(seekSeconds)s")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(seekSeconds) },
                    set: {
                        seekSeconds = Int($0)
                        updateAction()
                    }
                ),
                in: 1...90,
                step: 1
            )

            // Quick presets
            HStack(spacing: 8) {
                ForEach([5, 10, 15, 30, 45, 60], id: \.self) { seconds in
                    Button("\(seconds)s") {
                        seekSeconds = seconds
                        updateAction()
                    }
                    .buttonStyle(.bordered)
                    .tint(seekSeconds == seconds ? .accentColor : .secondary)
                    .controlSize(.small)
                }
            }
        }
    }

    private func updateAction() {
        action = selectedActionType.toAction(seconds: seekSeconds)
    }
}

#Preview {
    NavigationStack {
        TapZoneActionPicker(
            position: .left,
            action: .constant(.seekBackward(seconds: 10))
        )
    }
}
#endif
