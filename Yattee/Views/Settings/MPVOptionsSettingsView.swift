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
        SettingsFormContainer {
            if let settings = appEnvironment?.settingsManager {
                #if os(tvOS)
                CustomOptionsSection(
                    settings: settings,
                    showingAddSheet: $showingAddSheet,
                    editingOption: $editingOption
                )
                DefaultOptionsSection()
                #else
                DefaultOptionsSection()
                CustomOptionsSection(
                    settings: settings,
                    showingAddSheet: $showingAddSheet,
                    editingOption: $editingOption
                )
                #endif
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
    var body: some View {
        #if os(tvOS)
        SettingsFormSection(footer: "settings.mpvOptions.defaultOptions.footer") {
            Text(String(localized: "settings.mpvOptions.defaultOptions"))
                .font(.headline)
            ForEach(Self.defaultOptions, id: \.name) { option in
                LabeledContent(option.name) {
                    Text(option.value)
                        .foregroundStyle(.secondary)
                }
                .focusable()
            }
        }
        #else
        SettingsFormSection("settings.mpvOptions.defaultOptions", footer: "settings.mpvOptions.defaultOptions.footer") {
            ForEach(Self.defaultOptions, id: \.name) { option in
                HStack(alignment: .firstTextBaseline) {
                    Text(option.name)
                        .monospaced()
                    Spacer()
                    Text(option.value)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        #endif
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
        options.append(("ao", "coreaudio,avfoundation"))
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
        SettingsFormSection("settings.mpvOptions.customOptions", footer: "settings.mpvOptions.customOptions.footer") {
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
                        .contentShape(Rectangle())
                    }
                    #if os(macOS)
                    .buttonStyle(.plain)
                    #endif
                    #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            removeOption(named: name)
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                    #endif
                    .contextMenu {
                        Button(role: .destructive) {
                            removeOption(named: name)
                        } label: {
                            Label(String(localized: "common.delete"), systemImage: "trash")
                        }
                    }
                }
            }

            HStack {
                Button {
                    showingAddSheet = true
                } label: {
                    Label(String(localized: "settings.mpvOptions.addOption"), systemImage: "plus")
                }
                Spacer()
            }
        }
    }

    private func removeOption(named name: String) {
        var options = settings.customMPVOptions
        options.removeValue(forKey: name)
        settings.customMPVOptions = options
    }
}

// MARK: - Add MPV Option Sheet

private struct AddMPVOptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: SettingsManager

    @State private var optionName = ""
    @State private var optionValue = ""

    private var trimmedName: String {
        optionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedValue: String {
        optionValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty && !trimmedValue.isEmpty }

    private func save() {
        if canSave {
            var options = settings.customMPVOptions
            options[trimmedName] = trimmedValue
            settings.customMPVOptions = options
        }
        dismiss()
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.mpvOptions.addOption.title"))
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(String(localized: "settings.mpvOptions.optionName"))
                        .gridColumnAlignment(.trailing)
                    TextField("", text: $optionName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                GridRow {
                    Text(String(localized: "settings.mpvOptions.optionValue"))
                        .gridColumnAlignment(.trailing)
                    TextField("", text: $optionValue)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
            }

            Text(String(localized: "settings.mpvOptions.addOption.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "common.add")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        #elseif os(tvOS)
        VStack(spacing: 30) {
            Text(String(localized: "settings.mpvOptions.addOption.title"))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 20) {
                TextField(
                    String(localized: "settings.mpvOptions.optionName"),
                    text: $optionName
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                TextField(
                    String(localized: "settings.mpvOptions.optionValue"),
                    text: $optionValue
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Button {
                save()
            } label: {
                Text(String(localized: "common.add"))
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canSave)

            Text(String(localized: "settings.mpvOptions.addOption.footer"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(60)
        .frame(maxWidth: 900)
        #else
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "settings.mpvOptions.optionName"),
                        text: $optionName
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    TextField(
                        String(localized: "settings.mpvOptions.optionValue"),
                        text: $optionValue
                    )
                    .textInputAutocapitalization(.never)
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
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
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

    private var trimmedValue: String {
        optionValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedValue.isEmpty }

    private func save() {
        if canSave {
            var options = settings.customMPVOptions
            options[originalName] = trimmedValue
            settings.customMPVOptions = options
        }
        dismiss()
    }

    private func delete() {
        var options = settings.customMPVOptions
        options.removeValue(forKey: originalName)
        settings.customMPVOptions = options
        dismiss()
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.mpvOptions.editOption.title"))
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(String(localized: "settings.mpvOptions.optionName"))
                        .gridColumnAlignment(.trailing)
                    Text(originalName)
                        .monospaced()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text(String(localized: "settings.mpvOptions.optionValue"))
                        .gridColumnAlignment(.trailing)
                    TextField("", text: $optionValue)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
            }

            HStack {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(String(localized: "settings.mpvOptions.deleteOption"), systemImage: "trash")
                }

                Spacer()

                Button(String(localized: "common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "common.save")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .confirmationDialog(
            String(localized: "settings.mpvOptions.deleteOption.confirmation"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                delete()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .onAppear {
            optionValue = initialValue
        }
        #elseif os(tvOS)
        VStack(spacing: 30) {
            Text(String(localized: "settings.mpvOptions.editOption.title"))
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 20) {
                HStack {
                    Text(String(localized: "settings.mpvOptions.optionName"))
                    Spacer()
                    Text(originalName)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                TextField(
                    String(localized: "settings.mpvOptions.optionValue"),
                    text: $optionValue
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Button {
                save()
            } label: {
                Text(String(localized: "common.save"))
                    .frame(maxWidth: .infinity)
            }
            .disabled(!canSave)

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label(String(localized: "settings.mpvOptions.deleteOption"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(60)
        .frame(maxWidth: 900)
        .confirmationDialog(
            String(localized: "settings.mpvOptions.deleteOption.confirmation"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                delete()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        }
        .onAppear {
            optionValue = initialValue
        }
        #else
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
                    .textInputAutocapitalization(.never)
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
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                String(localized: "settings.mpvOptions.deleteOption.confirmation"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "common.delete"), role: .destructive) {
                    delete()
                }
                Button(String(localized: "common.cancel"), role: .cancel) {}
            }
            .presentationCompactAdaptation(.sheet)
        }
        .onAppear {
            optionValue = initialValue
        }
        #endif
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MPVOptionsSettingsView()
    }
    .appEnvironment(.preview)
}
