//
//  MPVOptionsSettingsView.swift
//  Yattee
//
//  Settings view for displaying and managing MPV options.
//

import SwiftUI

struct MPVOptionsSettingsView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var showingAddSheet = false
    @State private var editingOption: (name: String, value: String)?

    var body: some View {
        List {
            if let settings = appEnvironment?.settingsManager {
                DefaultOptionsSection()
                CustomOptionsSection(
                    settings: settings,
                    showingAddSheet: $showingAddSheet,
                    editingOption: $editingOption
                )
            }
        }
        .navigationTitle(String(localized: "settings.mpvOptions.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingAddSheet) {
            if let settings = appEnvironment?.settingsManager {
                AddMPVOptionSheet(settings: settings)
            }
        }
        .sheet(item: Binding(
            get: { editingOption.map { EditableOption(name: $0.name, value: $0.value) } },
            set: { editingOption = $0.map { ($0.name, $0.value) } }
        )) { option in
            if let settings = appEnvironment?.settingsManager {
                EditMPVOptionSheet(
                    settings: settings,
                    originalName: option.name,
                    initialValue: option.value
                )
            }
        }
    }
}

// MARK: - Identifiable wrapper for editing

private struct EditableOption: Identifiable {
    let name: String
    let value: String
    var id: String { name }
}

// MARK: - Default Options Section

private struct DefaultOptionsSection: View {
    #if !os(tvOS)
    @State private var isExpanded = false
    #endif

    var body: some View {
        Section {
            #if os(tvOS)
            Text(String(localized: "settings.mpvOptions.defaultOptions"))
                .font(.headline)
            ForEach(Self.defaultOptions, id: \.name) { option in
                LabeledContent(option.name) {
                    Text(option.value)
                        .foregroundStyle(.secondary)
                }
            }
            #else
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(Self.defaultOptions, id: \.name) { option in
                    LabeledContent(option.name) {
                        Text(option.value)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text(String(localized: "settings.mpvOptions.defaultOptions"))
            }
            #endif
        } footer: {
            Text(String(localized: "settings.mpvOptions.defaultOptions.footer"))
        }
    }

    /// Default MPV options from MPVClient.configureDefaultOptions()
    private static let defaultOptions: [(name: String, value: String)] = {
        var options: [(name: String, value: String)] = []

        options.append(("vo", "libmpv"))

        #if targetEnvironment(simulator)
        options.append(("hwdec", "no"))
        options.append(("sw-fast", "yes"))
        #else
        options.append(("hwdec", "videotoolbox-copy"))
        options.append(("hwdec-codecs", "h264,hevc,mpeg1video,mpeg2video,mpeg4,vp9,av1,prores"))
        #endif

        options.append(("keep-open", "yes"))
        options.append(("pause", "yes"))
        options.append(("target-prim", "bt.709"))
        options.append(("target-trc", "srgb"))
        options.append(("video-sync", "display-vdrop"))
        options.append(("framedrop", "decoder+vo"))
        options.append(("audio-client-name", "Yattee"))

        #if os(iOS) || os(tvOS)
        options.append(("ao", "audiounit"))
        #else
        options.append(("ao", "coreaudio"))
        #endif

        options.append(("cache", "yes"))
        options.append(("demuxer-max-bytes", "50MiB"))
        options.append(("demuxer-max-back-bytes", "25MiB"))

        return options
    }()
}

// MARK: - Custom Options Section

private struct CustomOptionsSection: View {
    @Bindable var settings: SettingsManager
    @Binding var showingAddSheet: Bool
    @Binding var editingOption: (name: String, value: String)?

    var body: some View {
        Section {
            let sortedOptions = settings.customMPVOptions.sorted { $0.key < $1.key }

            if sortedOptions.isEmpty {
                Text(String(localized: "settings.mpvOptions.customOptions.empty"))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedOptions, id: \.key) { name, value in
                    Button {
                        editingOption = (name, value)
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(value)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    var options = settings.customMPVOptions
                    for index in indexSet {
                        let key = sortedOptions[index].key
                        options.removeValue(forKey: key)
                    }
                    settings.customMPVOptions = options
                }
            }

            Button {
                showingAddSheet = true
            } label: {
                Label(String(localized: "settings.mpvOptions.addOption"), systemImage: "plus")
            }
        } header: {
            Text(String(localized: "settings.mpvOptions.customOptions"))
        } footer: {
            Text(String(localized: "settings.mpvOptions.customOptions.footer"))
        }
    }
}

// MARK: - Add MPV Option Sheet

private struct AddMPVOptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: SettingsManager

    @State private var optionName = ""
    @State private var optionValue = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "settings.mpvOptions.optionName"),
                        text: $optionName
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                    TextField(
                        String(localized: "settings.mpvOptions.optionValue"),
                        text: $optionValue
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                } footer: {
                    Text(String(localized: "settings.mpvOptions.addOption.footer"))
                }
            }
            .navigationTitle(String(localized: "settings.mpvOptions.addOption.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        let name = optionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let value = optionValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty && !value.isEmpty {
                            var options = settings.customMPVOptions
                            options[name] = value
                            settings.customMPVOptions = options
                        }
                        dismiss()
                    }
                    .disabled(optionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              optionValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 200)
        #endif
    }
}

// MARK: - Edit MPV Option Sheet

private struct EditMPVOptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: SettingsManager

    let originalName: String
    let initialValue: String

    @State private var optionValue = ""
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(String(localized: "settings.mpvOptions.optionName")) {
                        Text(originalName)
                    }

                    TextField(
                        String(localized: "settings.mpvOptions.optionValue"),
                        text: $optionValue
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "settings.mpvOptions.deleteOption"), systemImage: "trash")
                    }
                }
            }
            .navigationTitle(String(localized: "settings.mpvOptions.editOption.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        let value = optionValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty {
                            var options = settings.customMPVOptions
                            options[originalName] = value
                            settings.customMPVOptions = options
                        }
                        dismiss()
                    }
                    .disabled(optionValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                String(localized: "settings.mpvOptions.deleteOption.confirmation"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    var options = settings.customMPVOptions
                    options.removeValue(forKey: originalName)
                    settings.customMPVOptions = options
                    dismiss()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 200)
        #endif
        .onAppear {
            optionValue = initialValue
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MPVOptionsSettingsView()
    }
    .appEnvironment(.preview)
}
