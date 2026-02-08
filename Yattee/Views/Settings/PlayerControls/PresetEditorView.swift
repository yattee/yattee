//
//  PresetEditorView.swift
//  Yattee
//
//  Sheet view for creating, renaming, or duplicating a preset.
//

import SwiftUI

/// Mode for the preset editor.
enum PresetEditorMode {
    case create(baseLayouts: [LayoutPreset], activePreset: LayoutPreset?)
    case rename(currentName: String)

    var title: String {
        switch self {
        case .create:
            return String(localized: "settings.playerControls.newPreset")
        case .rename:
            return String(localized: "settings.playerControls.renamePreset")
        }
    }

    var placeholder: String {
        switch self {
        case .create, .rename:
            return String(localized: "settings.playerControls.presetNamePlaceholder")
        }
    }

    var initialValue: String {
        switch self {
        case .create:
            return ""
        case .rename(let currentName):
            return currentName
        }
    }

    var saveButtonTitle: String {
        switch self {
        case .create:
            return String(localized: "settings.playerControls.create")
        case .rename:
            return String(localized: "settings.playerControls.save")
        }
    }
}

/// Sheet view for creating or renaming a preset.
struct PresetEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: PresetEditorMode
    let onSave: (String, UUID?) -> Void

    @State private var name: String
    @State private var selectedBaseLayoutID: UUID?
    @FocusState private var isNameFocused: Bool

    private var baseLayouts: [LayoutPreset] {
        if case .create(let layouts, _) = mode {
            return layouts
        }
        return []
    }

    init(mode: PresetEditorMode, onSave: @escaping (String, UUID?) -> Void) {
        self.mode = mode
        self.onSave = onSave
        _name = State(initialValue: mode.initialValue)

        // Set default selection to active preset for create mode
        if case .create(_, let activePreset) = mode {
            _selectedBaseLayoutID = State(initialValue: activePreset?.id)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && trimmedName.count <= LayoutPreset.maxNameLength
    }

    var body: some View {
        NavigationStack {
            Form {
                // Base Layout Picker (only for create mode)
                if case .create(_, _) = mode {
                    Section {
                        Picker(
                            String(localized: "settings.playerControls.baseLayout"),
                            selection: $selectedBaseLayoutID
                        ) {
                            ForEach(baseLayouts) { preset in
                                Text(preset.name).tag(preset.id as UUID?)
                            }
                        }
                    }
                }

                Section {
                    TextField(mode.placeholder, text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(saveIfValid)
                } footer: {
                    HStack {
                        if trimmedName.count > LayoutPreset.maxNameLength {
                            Text(String(localized: "settings.playerControls.nameTooLong"))
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Text("\(trimmedName.count)/\(LayoutPreset.maxNameLength)")
                            .foregroundStyle(
                                trimmedName.count > LayoutPreset.maxNameLength ? .red : .secondary
                            )
                    }
                }
            }
            .navigationTitle(mode.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "settings.playerControls.cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.saveButtonTitle) {
                        saveIfValid()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    private func saveIfValid() {
        guard isValid else { return }
        onSave(trimmedName, selectedBaseLayoutID)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Create") {
    PresetEditorView(
        mode: .create(
            baseLayouts: LayoutPreset.allBuiltIn(),
            activePreset: LayoutPreset.defaultPreset()
        )
    ) { _, _ in }
}

#Preview("Rename") {
    PresetEditorView(mode: .rename(currentName: "My Custom Preset")) { _, _ in }
}
